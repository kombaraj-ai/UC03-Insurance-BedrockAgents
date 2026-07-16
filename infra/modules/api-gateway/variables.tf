variable "name_prefix" {
  type = string
}

variable "cors_allowed_origins" {
  description = "Exact frontend origin(s) allowed to call the API -- no wildcards."
  type        = list(string)
}

variable "cognito_user_pool_issuer" {
  type = string
}

variable "cognito_user_pool_client_id" {
  type = string
}

variable "client_api_lambda_invoke_arn" {
  type = string
}

variable "client_api_lambda_function_name" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "log_kms_key_arn" {
  type = string
}

variable "throttling_burst_limit" {
  type    = number
  default = 20
}

variable "throttling_rate_limit" {
  type    = number
  default = 10
}

variable "tags" {
  type    = map(string)
  default = {}
}
