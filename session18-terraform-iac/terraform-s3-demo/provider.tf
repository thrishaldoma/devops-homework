# AWS provider.
#
# There is no AWS account on this machine, so the provider is pointed at
# LocalStack - an AWS API emulator running in Docker on :4566. Every command the
# assignment asks for (init, fmt, validate, plan, apply, show, output, destroy)
# therefore executes for real against a real API implementation; only the cloud
# behind it is simulated.
#
# Setting use_localstack = false removes the endpoint overrides and the same
# configuration targets real AWS.
provider "aws" {
  region = var.aws_region

  # LocalStack accepts any credentials, but the provider still requires some.
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  # These three calls hit AWS metadata/STS endpoints that LocalStack does not
  # need; skipping them keeps plan/apply offline-friendly.
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # LocalStack serves buckets at /<bucket> rather than <bucket>.s3.amazonaws.com
  s3_use_path_style = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      s3       = var.localstack_endpoint
      iam      = var.localstack_endpoint
      sts      = var.localstack_endpoint
      ec2      = var.localstack_endpoint
      dynamodb = var.localstack_endpoint
    }
  }

  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = "Session18"
    }
  }
}
