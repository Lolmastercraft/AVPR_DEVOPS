#main.tf
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 4.0" }
  }
}
provider "aws" {
  region = var.aws_region
}

variable "aws_region"  { default = "us-east-1" }
variable "domain_name" {
  description = "Dominio registrado en Route53"
  default     = "tudominio.com"
}

# ────────────────────────────────────────────────────────────
# 1️⃣ VPC, Subred, IGW, Route Table, Asociación (igual a tu config)
resource "aws_vpc" "vpc_pro" {
  cidr_block = "10.13.0.0/20"
  tags       = { Name = "VPC-Pro" }
}
resource "aws_subnet" "subred_pub" {
  vpc_id                  = aws_vpc.vpc_pro.id
  cidr_block              = "10.13.0.0/24"
  map_public_ip_on_launch = true
  tags = { Name = "Subred-Pub" }
}
resource "aws_internet_gateway" "gateway_pro" {
  vpc_id = aws_vpc.vpc_pro.id
  tags   = { Name = "Gateway-Pro" }
}
resource "aws_route_table" "tablaruta_pub" {
  vpc_id = aws_vpc.vpc_pro.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway_pro.id
  }
  tags = { Name = "TablaRuta-Pro" }
}
resource "aws_route_table_association" "asoc_pub" {
  subnet_id      = aws_subnet.subred_pub.id
  route_table_id = aws_route_table.tablaruta_pub.id
}

# ────────────────────────────────────────────────────────────
# 2️⃣ Security Groups
resource "aws_security_group" "SG_JS_WIN" {
  vpc_id = aws_vpc.vpc_pro.id
  name   = "SG_JS_WIN"
  description = "Jump Server Windows"
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress { 
    from_port=0
    to_port=0
    protocol="-1"
    cidr_blocks=["0.0.0.0/0"]
    }
}
resource "aws_security_group" "SG_LIN_WEB" {
  vpc_id = aws_vpc.vpc_pro.id
  name   = "SG_LIN_WEB"
  description = "Servidor Web Linux"
  # SSH sólo desde Jump Server
  ingress {
    from_port                = 22
    to_port                  = 22
    protocol                 = "tcp"
    security_groups          = [aws_security_group.SG_JS_WIN.id]
  }
  # HTTP público
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # (opcional) Express directo en 3000
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port=0
    to_port=0
    protocol="-1"
    cidr_blocks=["0.0.0.0/0"]
    }
}

# ────────────────────────────────────────────────────────────
# 3️⃣ EC2 Instances
resource "aws_instance" "Win_JS" {
  ami                          = "ami-0c765d44cf1f25d26"
  instance_type                = "t2.medium"
  subnet_id                    = aws_subnet.subred_pub.id
  vpc_security_group_ids       = [aws_security_group.SG_JS_WIN.id]
  associate_public_ip_address  = true
  key_name                     = "vockey"
  tags = { Name = "Jump Server Windows" }
}
resource "aws_instance" "Lin_Web" {
  ami                          = "ami-084568db4383264d4"
  instance_type                = "t2.micro"
  subnet_id                    = aws_subnet.subred_pub.id
  vpc_security_group_ids       = [aws_security_group.SG_LIN_WEB.id]
  associate_public_ip_address  = true
  key_name                     = "vockey"
  iam_instance_profile         = aws_iam_instance_profile.ec2_dynamodb_profile.name
  tags = { Name = "Linux Web Server" }
}

# ────────────────────────────────────────────────────────────
# 4️⃣ Elastic IP para el Linux Web Server
resource "aws_eip" "linux_web_eip" {
  instance = aws_instance.Lin_Web.id
}

# ────────────────────────────────────────────────────────────
# 5️⃣ IAM Role + Profile para que EC2 hable con DynamoDB
resource "aws_iam_role" "ec2_dynamodb_role" {
  name = "EC2DynamoDBAccessRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect="Allow", Principal={Service="ec2.amazonaws.com"}, Action="sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "dynamodb_full_access" {
  role       = aws_iam_role.ec2_dynamodb_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}
resource "aws_iam_instance_profile" "ec2_dynamodb_profile" {
  name = "EC2DynamoDBProfile"
  role = aws_iam_role.ec2_dynamodb_role.name
}

# ────────────────────────────────────────────────────────────
# 6️⃣ VPC Endpoint para DynamoDB (tráfico interno)
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.vpc_pro.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.tablaruta_pub.id]
}

# ────────────────────────────────────────────────────────────
# 7️⃣ DynamoDB Tables: Admins y Productos
resource "aws_dynamodb_table" "admins" {
  name         = "Admins"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "email"

  attribute {
    name = "email"
    type = "S"
  }
}

resource "aws_dynamodb_table" "productos" {
  name         = "Productos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "autor"
    type = "S"
  }

  attribute {
    name = "album"
    type = "S"
  }
}


# ────────────────────────────────────────────────────────────
# 8️⃣ Route 53: Zona + Record “A” apuntando al EIP
resource "aws_route53_zone" "main" {
  name = var.domain_name
}
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [aws_eip.linux_web_eip.public_ip]
}

# ────────────────────────────────────────────────────────────
# 9️⃣ Outputs
output "url_web" {
  description = "URL de acceso público"
  value       = "http://${var.domain_name}"
}
