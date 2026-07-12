############################################
# S3 bucket for Mongo backups — INTENTIONALLY PUBLIC (weakness #3)
############################################
resource "aws_s3_bucket" "mongo_backups" {
  bucket = "${var.project_name}-mongo-backups-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-mongo-backups"
    Note = "Public read/list intentional for Wiz exercise"
  }
}

# Disable all public-access blocking - this is the intentional weakness
resource "aws_s3_bucket_public_access_block" "mongo_backups" {
  bucket                  = aws_s3_bucket.mongo_backups.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "mongo_backups_public" {
  bucket = aws_s3_bucket.mongo_backups.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadListIntentional"
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.mongo_backups.arn,
        "${aws_s3_bucket.mongo_backups.arn}/*"
      ]
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.mongo_backups]
}

# IAM policy granting the Mongo VM role permission to write backups
resource "aws_iam_policy" "mongo_backup_s3_write" {
  name = "${var.project_name}-mongo-backup-s3-write"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.mongo_backups.arn,
        "${aws_s3_bucket.mongo_backups.arn}/*"
      ]
    }]
  })
}

output "backup_bucket_name" {
  value = aws_s3_bucket.mongo_backups.bucket
}

output "backup_bucket_public_url" {
  value = "https://${aws_s3_bucket.mongo_backups.bucket}.s3.amazonaws.com/"
}
