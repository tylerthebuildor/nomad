provider "aws" {
  region = var.region
}

# Latest Ubuntu 24.04 LTS (arm64) from Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Network: an isolated VPC with a public subnet for OUTBOUND only. ---------
# The instance gets a public IP so it can reach the internet (package installs,
# Tailscale, the Anthropic API). The security group blocks all inbound, so the
# public IP is not an attack surface. Access is via Tailscale only.

resource "aws_vpc" "nomad" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}

resource "aws_internet_gateway" "nomad" {
  vpc_id = aws_vpc.nomad.id
  tags   = { Name = var.name }
}

resource "aws_subnet" "nomad" {
  vpc_id                  = aws_vpc.nomad.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = var.name }
}

resource "aws_route_table" "nomad" {
  vpc_id = aws_vpc.nomad.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.nomad.id
  }

  tags = { Name = var.name }
}

resource "aws_route_table_association" "nomad" {
  subnet_id      = aws_subnet.nomad.id
  route_table_id = aws_route_table.nomad.id
}

# Zero public inbound. No ingress rules = deny all inbound. Egress open.
resource "aws_security_group" "nomad" {
  name        = var.name
  description = "Nomad: zero public inbound, all egress. Access via Tailscale only."
  vpc_id      = aws_vpc.nomad.id

  egress {
    description = "All outbound (package installs, Tailscale, Anthropic API)."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = var.name }
}

# --- The box. ---------------------------------------------------------------
# No IAM instance profile on purpose: the box carries zero AWS credentials, so a
# compromise cannot touch the AWS account. Add a role later only if a real need
# appears (e.g. SSM break-glass or scoped S3 access).

resource "aws_instance" "nomad" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.nomad.id
  vpc_security_group_ids = [aws_security_group.nomad.id]

  # No key_name on purpose: there is no SSH key pair. Access is Tailscale SSH.

  user_data = templatefile("${path.module}/cloud-init.sh.tftpl", {
    tailscale_auth_key = var.tailscale_auth_key
    tailscale_hostname = var.tailscale_hostname
  })

  # Editing the bootstrap should NOT destroy the box (and its data). Re-run the
  # bootstrap manually over the tailnet instead.
  user_data_replace_on_change = false

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  lifecycle {
    # Both of these only matter when the box is created, and a change to either
    # would REPLACE the instance (wiping its disk) on the next `make up`:
    # - user_data: the auth key is used once at first boot. Re-bootstrap over the
    #   tailnet instead (make bootstrap).
    # - ami: the lookup above returns Canonical's newest image, which changes
    #   every few weeks. The running box patches itself in place (unattended
    #   upgrades). To move to a fresh image on purpose: terraform taint, then up.
    ignore_changes = [user_data, ami]
  }

  tags = { Name = var.name }
}
