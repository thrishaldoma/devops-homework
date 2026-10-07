# NOTE: an `output` block has no `type` argument. The course's outputs.tf
# declares `type = string` inside each output, which Terraform rejects with
# "Unsupported argument". Outputs infer their type from `value`.
output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.demo.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  description = "AWS region of the S3 bucket."
  value       = aws_s3_bucket.demo.region
}

output "versioning_status" {
  description = "Whether object versioning is enabled."
  value       = aws_s3_bucket_versioning.demo.versioning_configuration[0].status
}
