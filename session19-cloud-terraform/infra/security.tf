# ─────────────────────────────────────────────────────────────
#  Security groups, chained by reference rather than by CIDR.
#  web-sg is open to the internet; app-sg accepts traffic ONLY
#  from web-sg. That keeps working when instances are replaced
#  and their IPs change - a CIDR-based rule would not.
# ─────────────────────────────────────────────────────────────
resource "aws_security_group" "web" {
  name        = "${var.project}-web-sg"
  description = "Public tier: HTTP/HTTPS from the internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Note there is no port 22 rule. SSH open to 0.0.0.0/0 is the most common
  # AWS misconfiguration; use SSM Session Manager instead.

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-web-sg" }
}

resource "aws_security_group" "app" {
  name        = "${var.project}-app-sg"
  description = "Private tier: application port, reachable only from the web tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from the web tier only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id] # <- not a CIDR
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-app-sg" }
}
