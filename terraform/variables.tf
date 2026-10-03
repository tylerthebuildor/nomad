variable "region" {
  description = "AWS region for the Nomad box."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name/tag prefix for all resources."
  type        = string
  default     = "nomad"
}

variable "instance_type" {
  description = "EC2 instance type. ARM/Graviton. Start small, scale later."
  type        = string
  default     = "t4g.large"
}

variable "root_volume_gb" {
  description = "Root gp3 EBS volume size in GB. Grows live; size up later."
  type        = number
  default     = 100
}

variable "tailscale_hostname" {
  description = "Hostname the box registers on the tailnet (MagicDNS)."
  type        = string
  default     = "nomad"
}

variable "tailscale_auth_key" {
  description = "Single-use, non-ephemeral, short-expiry Tailscale auth key, used ONLY at first boot to join the tailnet. Pass via TF_VAR_tailscale_auth_key (make up prompts if unset); never commit. Empty is fine on re-runs since user_data is ignored after creation."
  type        = string
  sensitive   = true
  default     = ""
}
