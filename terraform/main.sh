terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-south-1"
}

# --- SSH Key Pair ---
data "aws_key_pair" "existing_key" {
  key_name = "jenkins-key"
}

# --- Use Existing VPC and Networking ---
data "aws_vpc" "existing_vpc" {
  id = "vpc-0332b471c442aae1c"  # Your existing VPC ID
}

data "aws_internet_gateway" "existing_igw" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
}

# Create NEW subnets in the existing VPC (using different CIDR blocks)
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = data.aws_vpc.existing_vpc.id
  cidr_block              = "10.0.10.0/24"  # Different from your existing 10.0.1.0/24
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "jenkins-public-subnet-a" }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = data.aws_vpc.existing_vpc.id
  cidr_block              = "10.0.11.0/24"  # Different CIDR
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true
  tags                    = { Name = "jenkins-public-subnet-b" }
}

resource "aws_subnet" "public_subnet_c" {
  vpc_id                  = data.aws_vpc.existing_vpc.id
  cidr_block              = "10.0.12.0/24"  # Different CIDR
  availability_zone       = "ap-south-1c"
  map_public_ip_on_launch = true
  tags                    = { Name = "jenkins-public-subnet-c" }
}

# Create a new route table for the new subnets
resource "aws_route_table" "new_public_rt" {
  vpc_id = data.aws_vpc.existing_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.existing_igw.id
  }
  tags = { Name = "jenkins-new-public-rt" }
}

# Associate new subnets with the new route table
resource "aws_route_table_association" "rta_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.new_public_rt.id
}

resource "aws_route_table_association" "rta_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.new_public_rt.id
}

resource "aws_route_table_association" "rta_c" {
  subnet_id      = aws_subnet.public_subnet_c.id
  route_table_id = aws_route_table.new_public_rt.id
}

# --- Security Group ---
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Allow SSH, HTTP, and Jenkins traffic"
  vpc_id      = data.aws_vpc.existing_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jenkins-sg" }
}

# --- IAM Role and Instance Profile ---
resource "aws_iam_role" "jenkins_role" {
  name = "jenkins-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_s3" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "jenkins_cw" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins-instance-profile"
  role = aws_iam_role.jenkins_role.name
}
resource "aws_iam_role_policy_attachment" "jenkins_ec2_readonly" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

# --- EC2 Instances ---
locals {
  jenkins_subnets = [
    aws_subnet.public_subnet_a.id,
    aws_subnet.public_subnet_b.id,
    aws_subnet.public_subnet_c.id
  ]
}

resource "aws_instance" "jenkins_ec2" {
  count                       = length(local.jenkins_subnets)
  ami                         = "ami-07f07a6e1060cd2a8"
  instance_type               = "t3.medium"
  subnet_id                   = local.jenkins_subnets[count.index]
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  key_name                    = data.aws_key_pair.existing_key.key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.jenkins_profile.name

  user_data = file("${path.module}/user_data.sh")

  root_block_device {
    volume_size = 25
    volume_type = "gp3"
  }

  tags = { Name = "jenkins-ec2-${count.index + 1}" }
}

# --- Outputs ---
output "jenkins_instance_public_ips" {
  description = "Public IP addresses of Jenkins EC2 instances"
  value       = aws_instance.jenkins_ec2[*].public_ip
}

output "new_subnet_ids" {
  description = "IDs of all new public subnets"
  value       = local.jenkins_subnets
}

output "vpc_id" {
  description = "VPC ID"
  value       = data.aws_vpc.existing_vpc.id
}

