# ---------------------------------------------------------
# Apex Federal Solutions
# Secure AWS Infrastructure - Terraform Portfolio Project
# ---------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "apex-secure-vpc"
    Environment = "dev"
    Project     = "secure-aws-infrastructure"
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# Public Subnet
# ---------------------------------------------------------

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name        = "apex-public-subnet"
    Environment = "dev"
    Project     = "secure-aws-infrastructure"
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# Private Subnet
# ---------------------------------------------------------

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name        = "apex-private-subnet"
    Environment = "dev"
    Project     = "secure-aws-infrastructure"
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------
# Internet Gateway
# -----------------------------------------------------

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "apex-internet-gateway"
    Environment = "dev"
    Project     = "secure-aws-infrastructure"
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------
# Public Route Table
# -----------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "apex-public-route-table"
    Environment = "dev"
    Project     = "secure-aws-infrastructure"
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------
# Public Route Table Association
# -----------------------------------------------------

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------
# Security Group
# ---------------------------------------------------------

resource "aws_security_group" "web_sg" {
  name        = "apex-web-sg"
  description = "Security group for web server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "apex-web-sg"
    Environment = "dev"
    Project     = "secure-aws-infrastructure"
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# EC2 Web Server
# ---------------------------------------------------------

resource "aws_instance" "web" {
  ami                    = "ami-0c101f26f147fa7fd"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd
              systemctl enable httpd
              systemctl start httpd

              echo "<h1>Apex Federal Solutions</h1>" > /var/www/html/index.html
              echo "<p>Secure AWS Infrastructure deployed with Terraform</p>" >> /var/www/html/index.html
              EOF

  tags = {
    Name        = "apex-web-server"
    Environment = "dev"
    Project     = "secure-aws-infrastructure"
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------
# Security Audit / Compliance Evidence S3 Bucket
# ------------------------------------------------------------

resource "aws_s3_bucket" "audit_logs" {
  bucket_prefix = "apex-security-audit-"

  tags = {
    Name        = "apex-security-audit"
    Environment = "dev"
    Project     = "secure-aws-infrastructure"
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------
# Block All Public Access to Audit Bucket
# ------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------
# Encrypt Audit Bucket at Rest
# ------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
# ------------------------------------------------------------
# Enable Versioning for Audit Bucket
# ------------------------------------------------------------

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ------------------------------------------------------------
# CloudTrail S3 Bucket Policy
# Allows AWS CloudTrail to write audit logs to the bucket
# ------------------------------------------------------------

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {

  statement {
    sid = "AWSCloudTrailAclCheck"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:GetBucketAcl"]

    resources = [
      aws_s3_bucket.audit_logs.arn
    ]
  }

  statement {
    sid = "AWSCloudTrailWrite"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "${aws_s3_bucket.audit_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}
data "aws_caller_identity" "current" {}
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.audit_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
}

# ============================================================
# CloudTrail - AWS API Activity Logging
# ============================================================

resource "aws_cloudtrail" "security_trail" {
  name                          = "apex-security-trail"
  s3_bucket_name                = aws_s3_bucket.audit_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  depends_on = [
    aws_s3_bucket_policy.cloudtrail
  ]

  tags = {
    Name        = "apex-security-trail"
    Environment = "dev"
    Project     = "secure-aws-infrastructure"
    ManagedBy   = "Terraform"
  }
}