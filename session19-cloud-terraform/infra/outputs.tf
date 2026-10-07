output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, keyed by AZ."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, keyed by AZ."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "web_security_group_id" {
  description = "ID of the public-tier security group."
  value       = aws_security_group.web.id
}

output "instance_id" {
  description = "ID of the web EC2 instance."
  value       = aws_instance.web.id
}

output "instance_private_ip" {
  description = "Private IP of the web instance."
  value       = aws_instance.web.private_ip
}

output "bucket_name" {
  description = "Name of the assets bucket."
  value       = aws_s3_bucket.assets.bucket
}

output "bucket_arn" {
  description = "ARN of the assets bucket."
  value       = aws_s3_bucket.assets.arn
}
