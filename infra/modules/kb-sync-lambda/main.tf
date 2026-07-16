# Wires the S3 event-driven auto-sync pipeline: whenever an object is
# created/removed in the KB source-docs bucket, the sync Lambda is invoked
# and calls bedrock-agent:StartIngestionJob -- no manual "Sync" click needed.
#
# Kept separate from modules/s3-secure-bucket (which is generic and reused
# for a bucket that does NOT need this notification) and from
# modules/lambda-function (which only builds the function itself, not its
# event source).

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3BucketNotification"
  action        = "lambda:InvokeFunction"
  function_name = var.sync_lambda_function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.source_bucket_arn
}

resource "aws_s3_bucket_notification" "kb_source_sync_trigger" {
  bucket = var.source_bucket_id

  lambda_function {
    lambda_function_arn = var.sync_lambda_function_arn
    events              = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}
