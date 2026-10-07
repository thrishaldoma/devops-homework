resource "aws_s3_bucket" "demo" {
  bucket        = var.bucket_name
  force_destroy = true # allows `terraform destroy` to remove a non-empty bucket

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
  }
}

# Block ALL public access. On real AWS this is the single most important S3
# setting - public buckets are the classic cloud data breach.
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning keeps previous object versions, which is what makes an accidental
# delete or a ransomware overwrite recoverable.
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest. SSE-S3 (AES256) is free and should always be on.
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
