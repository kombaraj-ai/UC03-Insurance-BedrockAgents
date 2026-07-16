variable "name" {
  description = "Short name used to build the key alias, e.g. \"autoclaim-iq-dev-logs\"."
  type        = string
}

variable "description" {
  description = "Human-readable description of what this key protects."
  type        = string
  default     = "CMK for CloudWatch Logs encryption"
}

variable "account_id" {
  description = "AWS account ID, used to scope the key's admin/usage policy statements."
  type        = string
}

variable "region" {
  description = "AWS region, used to scope the CloudWatch Logs service principal condition."
  type        = string
}

variable "deletion_window_in_days" {
  description = "Waiting period before the key is actually deleted after a destroy."
  type        = number
  default     = 30
}

variable "enable_key_rotation" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
