variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "alarm_email" {
  description = "Email address subscribed to the alarm SNS topic. Leave null to skip the subscription (topic is still created)."
  type        = string
  default     = null
}

variable "lambda_function_names" {
  description = "Map of a short label -> Lambda function name, used to build one set of error/throttle/duration alarms per function."
  type        = map(string)
}

variable "lambda_timeout_seconds" {
  description = "Map matching lambda_function_names' keys -> that function's configured timeout, used to set the duration alarm threshold at 80% of timeout."
  type        = map(number)
}

variable "api_id" {
  type = string
}

variable "api_name" {
  type = string
}

variable "dynamodb_table_names" {
  description = "Map of a short label -> DynamoDB table name, used to build one throttle alarm per table."
  type        = map(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
