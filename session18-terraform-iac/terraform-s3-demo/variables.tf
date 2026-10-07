variable "aws_region" {
  type        = string
  description = "AWS region where the S3 bucket will be created."
  default     = "ap-south-1"
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket. Must be globally unique on real AWS."
  default     = "yatri-session18-demo"

  validation {
    # S3 bucket naming rules: 3-63 chars, lowercase letters, digits, hyphens.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters, lowercase alphanumeric or hyphens, and start/end alphanumeric."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment tag."
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "use_localstack" {
  type        = bool
  description = "Target LocalStack instead of real AWS."
  default     = true
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge endpoint."
  default     = "http://localhost:4566"
}
