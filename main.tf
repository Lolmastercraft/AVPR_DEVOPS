# main.tf - Terraform configuration to provision AWS infrastructure
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "key_name" {
  description = "Name of an existing AWS Key Pair to use for EC2 SSH"
  type        = string
  # default is intentionally empty to force user to set their key name
  default     = ""
}

variable "db_password" {
  description = "Password for the RDS master user"
  type        = string
  default     = "VinylPass123!"
}

variable "domain_name" {
  description = "Domain name for Route53 (must be owned by user). Leave empty to skip Route53 setup."
  type        = string
  default     = ""
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "vinylstore-vpc" }
}

# Get two availability zones for subnets
data "aws_availability_zones" "azs" {
  state = "available"
}

# Public subnet in first AZ
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.azs.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "vinyl-public-subnet" }
}

# Private subnet in second AZ for RDS
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.azs.names[1]
  tags = { Name = "vinyl-private-subnet" }
}

# Internet Gateway for VPC
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "vinyl-igw" }
}

# Route table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "vinyl-public-rt" }
}

# Default route to Internet in public route table
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

# Associate public route table with public subnet
resource "aws_route_table_association" "pub_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group for EC2 (web server)
resource "aws_security_group" "web_sg" {
  name        = "vinyl-web-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = aws_vpc.main.id

  ingress = [
    { description = "SSH", from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    { description = "HTTP", from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  ]

  egress = [
    { description = "All outbound", from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  ]

  tags = { Name = "vinyl-web-sg" }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "vinyl-rds-sg"
  description = "Allow MySQL from EC2 web server"
  vpc_id      = aws_vpc.main.id

  ingress = [
    { description = "MySQL from web", from_port = 3306, to_port = 3306, protocol = "tcp",
      security_groups = [aws_security_group.web_sg.id] }
  ]
  egress = [
    { description = "All outbound", from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  ]

  tags = { Name = "vinyl-rds-sg" }
}

# Subnet group for RDS (requires subnets in at least two AZs)
resource "aws_db_subnet_group" "rds_subnets" {
  name       = "vinylstore-db-subnet-group"
  subnet_ids = [aws_subnet.public.id, aws_subnet.private.id]
  tags = { Name = "vinylstore-db-subnet-group" }
}

# RDS MySQL instance
resource "aws_db_instance" "mysql" {
  identifier        = "vinylstore-db"
  engine            = "mysql"
  engine_version    = "8.0"        # latest major version
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"
  username          = "admin"
  password          = var.db_password
  db_subnet_group_name = aws_db_subnet_group.rds_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  multi_az          = false
  publicly_accessible = false
  skip_final_snapshot = true

  tags = { Name = "vinylstore-db" }
}

# EC2 Instance for web server (Ubuntu)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name      = var.key_name

  # Install dependencies via user_data
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y python3-pip python3-dev build-essential libmysqlclient-dev mysql-client nginx git
              EOF

  tags = { Name = "vinylstore-web" }
}

# Route53 DNS (if domain_name is provided)
resource "aws_route53_zone" "zone" {
  count = length(var.domain_name) > 0 ? 1 : 0
  name  = var.domain_name
}

resource "aws_route53_record" "site" {
  count   = length(var.domain_name) > 0 ? 1 : 0
  zone_id = aws_route53_zone.zone[0].zone_id
  name    = ""                 # apex of the domain
  type    = "A"
  ttl     = 300
  records = [aws_instance.web.public_ip]
}

# Outputs
output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.mysql.address
}

output "site_url" {
  value = length(var.domain_name) > 0 ? "http://${var.domain_name}" : "http://${aws_instance.web.public_dns}"
}
