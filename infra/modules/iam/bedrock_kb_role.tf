# Role assumed by the Bedrock Knowledge Base. Scoped to: invoke only the
# embedding model, read only the KB source-docs bucket, and read/write only
# the specific S3 Vectors bucket/index backing this KB.

data "aws_iam_policy_document" "bedrock_kb_assume_role" {
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

resource "aws_iam_role" "bedrock_kb" {
  name               = "${var.name_prefix}-bedrock-kb-role"
  assume_role_policy = data.aws_iam_policy_document.bedrock_kb_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "bedrock_kb_policy" {
  statement {
    sid       = "InvokeEmbeddingModel"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = [var.kb_embedding_model_arn]
  }

  statement {
    sid       = "ReadSourceDocs"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.kb_source_bucket_arn, "${var.kb_source_bucket_arn}/*"]
  }

  # s3vectors:* access to the vector bucket/index is granted by
  # modules/kb-s3vectors (see this module's variables.tf note) since that
  # module owns the real vector bucket/index ARNs and already depends on
  # this role existing.
}

resource "aws_iam_role_policy" "bedrock_kb" {
  name   = "${var.name_prefix}-bedrock-kb-policy"
  role   = aws_iam_role.bedrock_kb.id
  policy = data.aws_iam_policy_document.bedrock_kb_policy.json
}
