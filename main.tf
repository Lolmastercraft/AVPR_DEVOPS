############################################
#        VARIABLES
############################################
variable "aws_region"       { default = "us-east-1" }
variable "existing_vpc_id"  { type = string }
variable "public_subnet_id" { type = string }
variable "key_name"         { type = string }
variable "db_password" {
  type        = string
  description = "RDS admin password"
  default     = "VinylPass123!"
}
variable "domain_name" {
  type        = string
  description = "Route53 domain (empty to skip DNS)"
  default     = ""
}

############################################
provider "aws" { region = var.aws_region }

############################################
# VPC Y SUBRED PÚBLICA EXISTENTES
############################################
data "aws_vpc"      "vpc"    { id = var.existing_vpc_id }
data "aws_subnet"   "pub"    { id = var.public_subnet_id }
data "aws_availability_zones" "azs" { state = "available" }

############################################
# SUBREDES PRIVADAS EN DOS AZ
############################################
locals {
  az_alt = [
    for az in data.aws_availability_zones.azs.names :
    az if az != data.aws_subnet.pub.availability_zone
  ][0]
}

resource "aws_subnet" "priv_a" {
  vpc_id            = data.aws_vpc.vpc.id
  cidr_block        = "10.13.1.0/24"
  availability_zone = data.aws_subnet.pub.availability_zone
  tags = { Name = "vinyl-priv-a" }
}

resource "aws_subnet" "priv_b" {
  vpc_id            = data.aws_vpc.vpc.id
  cidr_block        = "10.13.2.0/24"
  availability_zone = local.az_alt
  tags = { Name = "vinyl-priv-b" }
}

############################################
# SECURITY GROUPS
############################################
resource "aws_security_group" "web" {
  name        = "vinyl-web-sg"
  vpc_id      = data.aws_vpc.vpc.id
  revoke_rules_on_delete = true

  ingress { 
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }
  
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    }
  
  egress  {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }
  
  tags = { Name = "vinyl-web-sg" }
}

resource "aws_security_group" "rds" {
  name   = "vinyl-rds-sg"
  vpc_id = data.aws_vpc.vpc.id
  revoke_rules_on_delete = true

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
    description     = "MySQL from web"
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    }
  
  tags = { Name = "vinyl-rds-sg" }
}

############################################
# RDS SUBNET GROUP & INSTANCE
############################################
resource "aws_db_subnet_group" "rds" {
  name       = "vinyl-db-subnets"
  subnet_ids = [aws_subnet.priv_a.id, aws_subnet.priv_b.id]
}

resource "aws_db_instance" "mysql" {
  identifier              = "vinylstore-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  username                = "admin"
  password                = var.db_password
  db_name                 = "vinylstore"
  db_subnet_group_name    = aws_db_subnet_group.rds.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  tags = { Name = "vinylstore-db" }
}

############################################
# EC2 UBUNTU WEB SERVER
############################################
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name="name"
    values=["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
    }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = data.aws_subnet.pub.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = <<-EOS
              #!/bin/bash
              apt-get update -y
              apt-get install -y python3-pip python3-dev build-essential libmysqlclient-dev mysql-client nginx git
              EOS

  tags = { Name = "vinylstore-web" }
}

############################################
# ROUTE 53 (opcional)
############################################
resource "aws_route53_zone" "zone" {
  count = length(var.domain_name) > 0 ? 1 : 0
  name  = var.domain_name
}

resource "aws_route53_record" "site" {
  count   = length(var.domain_name) > 0 ? 1 : 0
  zone_id = aws_route53_zone.zone[0].zone_id
  name    = ""
  type    = "A"
  ttl     = 300
  records = [aws_instance.web.public_ip]
}

############################################
# OUTPUTS
############################################
output "ec2_public_ip" { value = aws_instance.web.public_ip }
output "rds_endpoint"  { value = aws_db_instance.mysql.address }
output "site_url" {
  value = length(var.domain_name) > 0 ? "http://${var.domain_name}" : "http://${aws_instance.web.public_dns}"
}
