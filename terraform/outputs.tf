output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.nomad.id
}

output "public_ip" {
  description = "Public IP for OUTBOUND only. Nothing can reach it inbound."
  value       = aws_instance.nomad.public_ip
}

output "tailscale_hostname" {
  description = "Reach the box at this MagicDNS name once it joins the tailnet."
  value       = var.tailscale_hostname
}

output "connect" {
  description = "How to connect once the box is on your tailnet."
  value       = "tailscale ssh ubuntu@${var.tailscale_hostname}"
}
