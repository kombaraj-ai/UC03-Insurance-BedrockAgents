variable "bucket_name" {
  description = "Explicit bucket name. Must be globally unique."
  type        = string
}

variable "versioning_enabled" {
  type    = bool
  default = true
}

variable "kms_key_arn" {
  description = "Optional CMK ARN for SSE-KMS. If null, uses SSE-S3 (AES256)."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete a non-empty bucket. Keep false for anything holding real data."
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "Optional list of lifecycle rule objects: { id, prefix, expiration_days, noncurrent_version_expiration_days }"
  type = list(object({
    id                                 = string
    prefix                             = optional(string, "")
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
  }))
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
