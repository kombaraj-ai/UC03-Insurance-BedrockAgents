# RAG pipeline storage: S3 Vectors (native S3 vector similarity search)
# instead of OpenSearch Serverless, per the corrected design from the
# reference conversation. Kept as its own module because this is the newest,
# least battle-tested part of the AWS provider surface used in this stack --
# isolating it means changes here don't risk the agent/action-group wiring.

resource "aws_s3vectors_vector_bucket" "kb" {
  vector_bucket_name = "${var.name_prefix}-kb-vectors-${var.account_id}"

  encryption_configuration {
    sse_type = "AES256"
  }

  tags = var.tags
}

resource "aws_s3vectors_index" "kb" {
  vector_bucket_name = aws_s3vectors_vector_bucket.kb.vector_bucket_name
  index_name         = "bedrock-kb-index"
  data_type          = "float32"
  dimension          = var.vector_dimension
  distance_metric    = var.distance_metric

  tags = var.tags
}

resource "aws_bedrockagent_knowledge_base" "this" {
  name        = "${var.name_prefix}-insurance-kb"
  description = "AutoClaim IQ policy/coverage/claims-process guidance, retrieved via RAG."
  role_arn    = var.kb_role_arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = var.embedding_model_arn
      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions = var.vector_dimension
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      vector_bucket_arn = aws_s3vectors_vector_bucket.kb.vector_bucket_arn
      index_arn         = aws_s3vectors_index.kb.index_arn
    }
  }

  tags = var.tags
}

resource "aws_bedrockagent_data_source" "s3_docs" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.this.id
  name              = "S3PolicyDocuments"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = var.kb_source_bucket_arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = var.chunking_max_tokens
        overlap_percentage = var.chunking_overlap_percentage
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Supplemental IAM policies, attached here rather than in modules/iam.
#
# This module already depends on modules/iam for kb_role_arn (the KB
# resource's role_arn), so it's a one-directional dependency (kb-s3vectors ->
# iam). If modules/iam also tried to grant permissions on THIS module's real
# ARNs (the KB, the vector bucket/index), that would create a cycle
# (iam -> kb-s3vectors -> iam). Attaching these three permissions here
# instead -- where the real ARNs are locally available as resource
# attributes -- avoids that cycle entirely.
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "kb_role_vector_store_access" {
  name = "${var.name_prefix}-kb-role-vector-access"
  role = var.kb_role_name

  # Exact s3vectors action set per the AWS S3 Vectors IAM reference --
  # verify against current docs at apply time, this surface is new.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "UseVectorStore"
        Effect = "Allow"
        Action = [
          "s3vectors:PutVectors",
          "s3vectors:GetVectors",
          "s3vectors:QueryVectors",
          "s3vectors:DeleteVectors",
          "s3vectors:GetIndex",
          "s3vectors:ListVectors",
        ]
        Resource = [
          aws_s3vectors_vector_bucket.kb.vector_bucket_arn,
          aws_s3vectors_index.kb.index_arn,
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "agent_role_kb_retrieve" {
  name = "${var.name_prefix}-agent-role-kb-retrieve"
  role = var.bedrock_agent_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RetrieveFromKnowledgeBase"
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
        Resource = aws_bedrockagent_knowledge_base.this.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "kb_sync_lambda_role_ingestion" {
  name = "${var.name_prefix}-kb-sync-role-ingestion"
  role = var.kb_sync_lambda_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TriggerIngestion"
        Effect   = "Allow"
        Action   = ["bedrock:StartIngestionJob", "bedrock:GetIngestionJob"]
        Resource = aws_bedrockagent_knowledge_base.this.arn
      }
    ]
  })
}
