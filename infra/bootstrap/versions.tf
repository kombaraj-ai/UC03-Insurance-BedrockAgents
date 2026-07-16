terraform {
  required_version = "= 1.15.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.27.0"
    }
  }

  # Intentionally NO backend block here. This configuration creates the
  # remote state backend (S3 bucket + DynamoDB lock table) used by every
  # other configuration in this repo, so it cannot depend on that backend
  # existing yet -- it manages its own small local state file instead.
  #
  # This directory is applied exactly once, by hand, and is not part of the
  # normal day-to-day workflow. See README.md in this directory before
  # touching anything here.
}
