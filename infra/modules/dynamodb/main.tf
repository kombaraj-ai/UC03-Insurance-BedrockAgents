# Data layer for AutoClaim IQ. Kept as its own module, separate from
# everything else that churns (Lambda code, agent config), because these two
# tables hold real customer/claims data -- `prevent_destroy` and a higher
# bar for review should apply here independent of infra changes elsewhere.
#
# Encryption uses the AWS-owned DynamoDB key (server_side_encryption.enabled
# = true, no kms_key_arn) rather than a customer-managed CMK. This is a
# deliberate, documented trade-off (see docs/decision-log.md /
# README "Security Review" section) -- only CloudWatch Logs get a CMK in
# this build.

resource "aws_dynamodb_table" "policies" {
  name         = "${var.name_prefix}-Policies"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "policyId"

  attribute {
    name = "policyId"
    type = "S"
  }

  attribute {
    name = "lastName"
    type = "S"
  }

  # Ops/support lookup path only ("find a policy by last name"). The actual
  # customer-facing verify flow (services/policy_handler) never queries this
  # GSI with unverified caller input -- it does GetItem(policyId) first, then
  # compares lastName in application code, so an unverified caller can't use
  # this index to enumerate policies by guessing names.
  global_secondary_index {
    name            = "LastNameIndex"
    projection_type = "ALL"

    key_schema {
      attribute_name = "lastName"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "policyId"
      key_type       = "RANGE"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-Policies" })
}

resource "aws_dynamodb_table" "claims" {
  name             = "${var.name_prefix}-Claims"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "claimNumber"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "claimNumber"
    type = "S"
  }

  attribute {
    name = "policyId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  # Supports "list claims for a given policy, most recent first".
  global_secondary_index {
    name            = "PolicyIdIndex"
    projection_type = "ALL"

    key_schema {
      attribute_name = "policyId"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "createdAt"
      key_type       = "RANGE"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-Claims" })
}
