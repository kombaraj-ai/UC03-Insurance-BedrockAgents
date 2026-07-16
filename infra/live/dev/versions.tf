terraform {
  required_version = "= 1.15.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.27.0" # minimum version carrying S3 Vectors + Bedrock Guardrail resources
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }

  backend "s3" {
    # Filled in from `infra/bootstrap` outputs. Either edit these values
    # directly after running the bootstrap, or pass them via
    # `-backend-config` flags on `terraform init` (see README.md).
    bucket         = "REPLACE_WITH_BOOTSTRAP_STATE_BUCKET_NAME"
    key            = "autoclaim-iq/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "autoclaim-iq-terraform-locks"
    encrypt        = true
  }
}
