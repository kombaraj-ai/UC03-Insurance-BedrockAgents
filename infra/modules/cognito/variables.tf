variable "name_prefix" {
  type = string
}

variable "callback_urls" {
  description = "Exact OAuth callback URLs for the app client -- no wildcards."
  type        = list(string)
}

variable "logout_urls" {
  type    = list(string)
  default = []
}

variable "mfa_configuration" {
  description = "\"OFF\", \"ON\", or \"OPTIONAL\". Default OPTIONAL; set to \"ON\" if the org mandates MFA."
  type        = string
  default     = "OPTIONAL"
}

variable "tags" {
  type    = map(string)
  default = {}
}
