# ---------------------------------------------------------------------------
# Policy handler Lambda: read-only against Policies. This function only
# verifies identity -- it must never be able to write/delete a policy.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "policy_lambda" {
  name               = "${var.name_prefix}-policy-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "policy_lambda_policy" {
  statement {
    sid       = "ReadPolicies"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:Query"]
    resources = [var.policies_table_arn, var.policies_table_lastname_gsi_arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.policy_log_group_arn]
  }

  statement {
    sid       = "UseLogEncryptionKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_log_key_arn]
  }
}

resource "aws_iam_role_policy" "policy_lambda" {
  name   = "${var.name_prefix}-policy-lambda-policy"
  role   = aws_iam_role.policy_lambda.id
  policy = data.aws_iam_policy_document.policy_lambda_policy.json
}

# ---------------------------------------------------------------------------
# Claims handler Lambda: read/write Claims, read-only Policies (to validate
# ACTIVE status before creating a claim -- never write access to Policies).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "claims_lambda" {
  name               = "${var.name_prefix}-claims-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "claims_lambda_policy" {
  statement {
    sid    = "ReadWriteClaims"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
    ]
    resources = [var.claims_table_arn, var.claims_table_policyid_gsi_arn]
  }

  statement {
    sid       = "ReadOnlyPolicies"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem"]
    resources = [var.policies_table_arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.claims_log_group_arn]
  }

  statement {
    sid       = "UseLogEncryptionKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_log_key_arn]
  }
}

resource "aws_iam_role_policy" "claims_lambda" {
  name   = "${var.name_prefix}-claims-lambda-policy"
  role   = aws_iam_role.claims_lambda.id
  policy = data.aws_iam_policy_document.claims_lambda_policy.json
}

# ---------------------------------------------------------------------------
# KB auto-sync Lambda: only allowed to kick off/inspect an ingestion job and
# read the source bucket it was triggered from.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "kb_sync_lambda" {
  name               = "${var.name_prefix}-kb-sync-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "kb_sync_lambda_policy" {
  # StartIngestionJob/GetIngestionJob is granted by modules/kb-s3vectors
  # (see this module's variables.tf note) since that module owns the KB's
  # real ARN and already depends on this role existing.

  statement {
    sid       = "ReadSourceBucket"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.kb_source_bucket_arn}/*"]
  }

  statement {
    sid       = "WriteOwnLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.kb_sync_log_group_arn]
  }

  statement {
    sid       = "UseLogEncryptionKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_log_key_arn]
  }
}

resource "aws_iam_role_policy" "kb_sync_lambda" {
  name   = "${var.name_prefix}-kb-sync-lambda-policy"
  role   = aws_iam_role.kb_sync_lambda.id
  policy = data.aws_iam_policy_document.kb_sync_lambda_policy.json
}

# ---------------------------------------------------------------------------
# Client API Lambda: the only identity allowed to call InvokeAgent, scoped to
# exactly this agent + its alias (never Resource = ["*"]).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "client_api_lambda" {
  name               = "${var.name_prefix}-client-api-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "client_api_lambda_policy" {
  # InvokeAgent is granted by modules/bedrock-agent (see this module's
  # variables.tf note) since that module owns the agent/alias's real ARNs
  # and already depends on this role existing.

  statement {
    sid       = "WriteOwnLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [local.client_api_log_group_arn]
  }

  statement {
    sid       = "UseLogEncryptionKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_log_key_arn]
  }
}

resource "aws_iam_role_policy" "client_api_lambda" {
  name   = "${var.name_prefix}-client-api-lambda-policy"
  role   = aws_iam_role.client_api_lambda.id
  policy = data.aws_iam_policy_document.client_api_lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "client_api_lambda_xray" {
  role       = aws_iam_role.client_api_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "policy_lambda_xray" {
  role       = aws_iam_role.policy_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "claims_lambda_xray" {
  role       = aws_iam_role.claims_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "kb_sync_lambda_xray" {
  role       = aws_iam_role.kb_sync_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
