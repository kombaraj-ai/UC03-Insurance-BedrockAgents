#!/usr/bin/env bash
# Uploads the sample Knowledge Base documents to the KB source bucket.
# This upload is what triggers the auto-sync pipeline (S3 event -> sync
# Lambda -> StartIngestionJob) -- no manual "Sync" click needed afterward.
#
# Usage:
#   ./upload_seed_docs.sh <kb-source-bucket-name> [region]
#
# The bucket name is a Terraform output: `terraform output -raw kb_source_bucket_name`
set -euo pipefail

BUCKET="${1:?Usage: upload_seed_docs.sh <kb-source-bucket-name> [region]}"
REGION="${2:-us-east-1}"

aws s3 cp "$(dirname "$0")/seed-docs/" "s3://${BUCKET}/" --recursive --region "$REGION"

echo "Uploaded seed docs to s3://${BUCKET}/. Check the Knowledge Base's data source sync history to confirm ingestion started automatically."
