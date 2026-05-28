# Jenkins Infrastructure on AWS
provider "aws" {
  region = var.aws_region
}

# Jenkins Master EC2 instance
resource "aws_instance" "jenkins_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.xlarge"
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins.name
  key_name               = var.key_name

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = false
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    
    # Install Jenkins
    wget -q -O /usr/share/keyrings/jenkins-keyring.asc \
      https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
      https://pkg.jenkins.io/debian-stable binary/ | tee /etc/apt/sources.list.d/jenkins.list
    
    apt-get update -q
    apt-get install -y openjdk-17-jre-headless jenkins docker.io kubectl helm
    
    # Configure Jenkins
    systemctl enable --now jenkins
    usermod -aG docker jenkins
    
    # Install plugins
    jenkins-plugin-cli --plugins \
      kubernetes:4029.v5712230ccb_f5 \
      workflow-aggregator:600.vb_57cdd26fdd7 \
      git:5.2.1 \
      blueocean:1.27.9 \
      sonar:2.17.2 \
      slack:693.v3b_f7d975f9d9 \
      ansicolor:1.0.2 \
      build-timeout:1.31 \
      timestamper:1.26
    
    systemctl restart jenkins
  EOF

  tags = {
    Name        = "jenkins-master"
    Role        = "ci-cd"
    Environment = "tools"
    ManagedBy   = "terraform"
  }
}

# EFS for Jenkins home
resource "aws_efs_file_system" "jenkins_home" {
  creation_token = "jenkins-home"
  encrypted      = true
  kms_key_id     = var.kms_key_arn
  
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = { Name = "jenkins-home-efs" }
}

resource "aws_efs_mount_target" "jenkins" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.jenkins_home.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# IAM Role for Jenkins
resource "aws_iam_role" "jenkins" {
  name = "jenkins-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "jenkins" {
  name = "jenkins-policy"
  role = aws_iam_role.jenkins.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:*", "eks:Describe*", "eks:List*", "s3:GetObject", "s3:PutObject"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "jenkins-profile"
  role = aws_iam_role.jenkins.name
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "jenkins" {
  name_prefix = "jenkins-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Jenkins agent JNLP port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "efs" {
  name_prefix = "jenkins-efs-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }
}

variable "aws_region"         { default = "us-east-1" }
variable "vpc_id"             { type = string }
variable "vpc_cidr"           { type = string }
variable "private_subnet_id"  { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "allowed_cidrs"      { type = list(string) }
variable "key_name"           { type = string }
variable "kms_key_arn"        { type = string }

output "jenkins_private_ip"   { value = aws_instance.jenkins_master.private_ip }
output "efs_dns_name"         { value = aws_efs_file_system.jenkins_home.dns_name }
