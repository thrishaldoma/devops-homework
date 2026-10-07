# Look the AMI up rather than hardcoding it: AMI IDs are region-specific, so a
# literal would break the moment aws_region changes.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  # Implicit dependencies: Terraform reads these references and works out that
  # the subnet and security group must exist first. No depends_on needed.
  subnet_id              = aws_subnet.public[var.availability_zones[0]].id
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y nginx
    echo "<h1>${var.project} web tier</h1>" > /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOT

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3" # gp3 decouples IOPS from size; cheaper than gp2
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only - mitigates SSRF credential theft
  }

  tags = { Name = "${var.project}-web" }
}
