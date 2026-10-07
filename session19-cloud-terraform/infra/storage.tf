# Bucket names are globally unique on AWS, so suffix with a random value rather
# than risking a collision.
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket        = "${var.project}-assets-${random_id.suffix.hex}"
  force_destroy = true

  tags = { Name = "${var.project}-assets" }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# An EXPLICIT dependency, to show the difference. Nothing in this object
# references the instance, so Terraform could otherwise create it first;
# depends_on forces the ordering.
resource "aws_s3_object" "readme" {
  bucket  = aws_s3_bucket.assets.id
  key     = "README.txt"
  content = "Assets bucket for ${var.project} (${var.environment}).\n"

  depends_on = [aws_instance.web]
}
