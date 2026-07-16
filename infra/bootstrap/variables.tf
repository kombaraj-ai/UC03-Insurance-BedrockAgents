variable "aws_region" {
  description = "AWS region to create the Terraform state backend in."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project slug used to name/prefix backend resources."
  type        = string
  default     = "autoclaim-iq"
}

variable "state_bucket_name" {
  description = <<-EOT
    Globally-unique S3 bucket name for Terraform remote state. S3 bucket
    names are global across all AWS accounts, so the default below appends
    the caller's account ID to reduce collision risk -- override explicitly
    if you want a specific name.
  EOT
  type        = string
  default     = null
}

variable "lock_table_name" {
  description = "DynamoDB table name used for Terraform state locking."
  type        = string
  default     = "autoclaim-iq-terraform-locks"
}

variable "tags" {
  description = "Common tags applied to all bootstrap resources."
  type        = map(string)
  default = {
    Project   = "autoclaim-iq"
    ManagedBy = "terraform"
    Scope     = "bootstrap"
  }
}
