terraform {
  # Partial config: bucket/key/region come from backend.hcl at `terraform init`.
  # See backend.hcl.example. Uses S3-native state locking (use_lockfile), so no
  # DynamoDB table is needed (Terraform >= 1.11).
  backend "s3" {}
}
