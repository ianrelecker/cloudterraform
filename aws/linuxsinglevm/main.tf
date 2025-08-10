terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  
  backend "s3" {
    bucket = "terraform-state-cloudterraform"
    key    = "linux-t3-micro-vm.terraform.tfstate"
    region = "us-west-2"
  }
}

provider "aws" {
  region = var.region
}

# -------- Vars (override via -var or tfvars) ----------
variable "prefix"            { default = "linux-t3-micro" }
variable "region"            { default = "us-west-2" }
variable "instance_type"     { default = "t3.micro" }
variable "github_username"   { 
  description = "GitHub username to fetch SSH public keys from"
  type        = string
}
variable "vpc_cidr"          { default = "10.60.0.0/16" }
variable "subnet_cidr"       { default = "10.60.1.0/24" }
variable "allowed_ssh_cidr"  { default = "0.0.0.0/0" }
variable "create_public_ip"  { default = true }

# ----------------- Data Sources -----------------
data "http" "github_ssh_keys" {
  url = "https://github.com/${var.github_username}.keys"
  request_headers = {
    Accept = "text/plain"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  all_keys = split("\n", trimspace(data.http.github_ssh_keys.response_body))
  valid_keys = [for key in local.all_keys : key if length(trimspace(key)) > 0 && can(regex("^ssh-rsa", key))]
  selected_key = length(local.valid_keys) > 0 ? local.valid_keys[0] : ""
}

# ----------------- Network -----------------
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.prefix}-vpc"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = var.create_public_ip

  tags = {
    Name = "${var.prefix}-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  count  = var.create_public_ip ? 1 : 0
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.prefix}-igw"
  }
}

resource "aws_route_table" "rt" {
  count  = var.create_public_ip ? 1 : 0
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }

  tags = {
    Name = "${var.prefix}-rt"
  }
}

resource "aws_route_table_association" "rta" {
  count          = var.create_public_ip ? 1 : 0
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.rt[0].id
}

resource "aws_security_group" "sg" {
  name        = "${var.prefix}-sg"
  description = "Security group for ${var.prefix} instance"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}-sg"
  }
}

# ----------------- Key Pair -----------------
resource "aws_key_pair" "key_pair" {
  key_name   = "${var.prefix}-key"
  public_key = local.selected_key

  tags = {
    Name = "${var.prefix}-key"
  }
}

# ----------------- EC2 Instance -----------------
resource "aws_instance" "instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.sg.id]
  subnet_id              = aws_subnet.subnet.id

  user_data = base64encode(file("${path.module}/cloud-init.yaml"))

  tags = {
    Name = "${var.prefix}-instance"
  }
}

# --------------- Output ---------------
output "private_ip" { value = aws_instance.instance.private_ip }
output "public_ip"  { value = var.create_public_ip ? aws_instance.instance.public_ip : null }
output "instance_id" { value = aws_instance.instance.id }