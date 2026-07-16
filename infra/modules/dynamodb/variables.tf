variable "name_prefix" {
  description = "Prefix applied to both table names, e.g. \"autoclaim-iq-dev\"."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
