# Role assumed by the Bedrock Agent itself. Scoped to: invoke the specific
# foundation model / inference profile in use, retrieve from the specific
# Knowledge Base, apply the specific Guardrail, and invoke exactly the two
# action-group Lambdas -- never Resource = ["*"].

data "aws_iam_policy_document" "bedrock_agent_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "bedrock_agent" {
  name               = "${var.name_prefix}-bedrock-agent-role"
  assume_role_policy = data.aws_iam_policy_document.bedrock_agent_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "bedrock_agent_policy" {
  statement {
    sid       = "InvokeFoundationModel"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = var.model_invoke_arns
  }

  # Retrieve/RetrieveAndGenerate on the Knowledge Base is granted by
  # modules/kb-s3vectors (see this module's variables.tf note) since that
  # module owns the KB's real ARN and already depends on this role existing.

  statement {
    sid       = "ApplyGuardrail"
    effect    = "Allow"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [var.guardrail_arn]
  }

  statement {
    sid       = "InvokeActionGroupLambdas"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [local.policy_lambda_arn, local.claims_lambda_arn]
  }
}

resource "aws_iam_role_policy" "bedrock_agent" {
  name   = "${var.name_prefix}-bedrock-agent-policy"
  role   = aws_iam_role.bedrock_agent.id
  policy = data.aws_iam_policy_document.bedrock_agent_policy.json
}
