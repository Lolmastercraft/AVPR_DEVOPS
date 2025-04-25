############################
# VARIABLES
############################
variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "existing_vpc_id" {
  description = "ID de la VPC 10.13.0.0/20"
}

variable "public_subnet_id" {
  description = "ID de la subred pública 10.13.0.0/24"
}

variable "key_name" {
  description = "KeyPair para SSH"
}

variable "db_password" {
  description = "Contraseña RDS"
  default     = "VinylPass123!"
}

variable "domain_name" {
  description = "Dominio (Route53). Vacío para omitir"
  default     = ""
}


############################################################
# PROVIDER
############################################################
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
provider "aws" { region = var.aws_region }

############################################################
# VPC Y SUBRED PÚBLICA EXISTENTES
############################################################
data "aws_vpc" "main"          { id = var.existing_vpc_id }
data "aws_subnet" "public"     { id = var.public_subnet_id }

############################################################
# SUBRED PRIVADA PARA RDS (10.13.1.0/24)
############################################################
resource "aws_subnet" "private" {
  vpc_id                  = data.aws_vpc.main.id
  cidr_block              = "10.13.1.0/24"
  availability_zone       = data.aws_subnet.public.availability_zone
  map_public_ip_on_launch = false
  tags = { Name = "vinyl-private-subnet" }
}

############################################################
# SECURITY GROUPS
############################################################
resource "aws_security_group" "web_sg" {
  name        = "vinyl-web-sg"
  description = "Allow SSH (22) + HTTP (80)"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "vinyl-web-sg" }
}

resource "aws_security_group" "rds_sg" {
  name        = "vinyl-rds-sg"
  description = "Allow MySQL from web SG"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description       = "MySQL from web"
    from_port         = 3306
    to_port           = 3306
    protocol          = "tcp"
    security_groups   = [aws_security_group.web_sg.id]
  }
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "vinyl-rds-sg" }
}

############################################################
# RDS SUBNET GROUP (pública + privada)
############################################################
resource "aws_db_subnet_group" "rds_subnets" {
  name       = "vinylstore-db-subnet-group"
  subnet_ids = [data.aws_subnet.public.id, aws_subnet.private.id]
  tags       = { Name = "vinylstore-db-subnet-group" }
}

############################################################
# RDS MySQL
############################################################
resource "aws_db_instance" "mysql" {
  identifier              = "vinylstore-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp2"
  username                = "admin"
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.rds_subnets.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  publicly_accessible     = false
  multi_az                = false
  skip_final_snapshot     = true

  db_name = "vinylstore"          # ← aquí, no "name"

  tags = { Name = "vinylstore-db" }
}


############################################################
# EC2 UBUNTU WEB SERVER
############################################################
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y python3-pip python3-dev build-essential libmysqlclient-dev mysql-client nginx git
              EOF

  tags = { Name = "vinylstore-web" }
}

############################################################
# ROUTE 53 (opcional)
############################################################
resource "aws_route53_zone" "zone" {
  count = length(var.domain_name) > 0 ? 1 : 0
  name  = var.domain_name
}

resource "aws_route53_record" "site" {
  count   = length(var.domain_name) > 0 ? 1 : 0
  zone_id = aws_route53_zone.zone[0].zone_id
  name    = ""  # registro APEX
  type    = "A"
  ttl     = 300
  records = [aws_instance.web.public_ip]
}

############################################################
# OUTPUTS
############################################################
output "ec2_public_ip" { value = aws_instance.web.public_ip }
output "rds_endpoint"  { value = aws_db_instance.mysql.address }
output "site_url" {
  value = length(var.domain_name) > 0 ? "http://${var.domain_name}" : "http://${aws_instance.web.public_dns}"
}

