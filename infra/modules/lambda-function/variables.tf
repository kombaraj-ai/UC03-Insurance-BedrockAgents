variable "function_name" {
  type = string
}

variable "description" {
  type    = string
  default = ""
}

variable "source_dir" {
  description = "Path to the Lambda's src/ directory (files land at the zip root, matching `handler.lambda_handler`)."
  type        = string
}

variable "handler" {
  type    = string
  default = "handler.lambda_handler"
}

variable "runtime" {
  type    = string
  default = "python3.12"
}

variable "role_arn" {
  description = "IAM role ARN for this function, supplied by the root module from modules/iam."
  type        = string
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "memory_size" {
  type    = number
  default = 256
}

variable "timeout" {
  type    = number
  default = 30
}

variable "reserved_concurrent_executions" {
  description = "-1 (default) means unreserved/unlimited, subject to the account pool."
  type        = number
  default     = -1
}

variable "tracing_mode" {
  description = "X-Ray tracing mode: \"Active\" or \"PassThrough\"."
  type        = string
  default     = "Active"
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "log_kms_key_arn" {
  description = "CMK ARN used to encrypt this function's CloudWatch Log Group."
  type        = string
}

variable "maximum_retry_attempts" {
  description = "Async invocation retry attempts (0-2). Use 0 for Lambdas invoked synchronously by Bedrock/API Gateway, since the caller handles its own retry/error surfacing."
  type        = number
  default     = 0
}

variable "dead_letter_target_arn" {
  description = "Optional SQS/SNS ARN for failed async invocations."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
