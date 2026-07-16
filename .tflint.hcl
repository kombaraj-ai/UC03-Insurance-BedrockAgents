plugin "aws" {
  enabled = true
  version = "0.35.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  format = "compact"
  call_module_type = "local"
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = false # this repo documents intent via comments + README, not a lint-enforced convention
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}
