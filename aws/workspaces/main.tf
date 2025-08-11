terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  
  backend "s3" {
    bucket = "terraform-state-cloudterraform"
    key    = "workspaces.terraform.tfstate"
    region = "us-west-2"
  }
}

provider "aws" {
  region = local.region
}

# -------- Load config from YAML ----------
locals {
  config_file = fileexists("${path.module}/workspaces-config.yaml") ? yamldecode(file("${path.module}/workspaces-config.yaml")) : {
    prefix = null
    region = null
    vpc_cidr = null
    subnet_a_cidr = null
    subnet_b_cidr = null
    directory_name = null
    directory_password = null
    directory_size = null
    enable_internet_access = null
    default_ou = null
    bundle_id = null
    user_name = null
    workspace_properties = null
  }
}

# -------- Vars (override via -var or tfvars) ----------
variable "prefix" { 
  default = null
  type = string
}
variable "region" { 
  default = null
  type = string
}
variable "vpc_cidr" {
  description = "CIDR block for WorkSpaces VPC"
  default = null
  type = string
}
variable "subnet_a_cidr" {
  description = "CIDR block for subnet A"
  default = null
  type = string
}
variable "subnet_b_cidr" {
  description = "CIDR block for subnet B"
  default = null
  type = string
}
variable "directory_name" {
  description = "Name for the directory"
  default = null
  type = string
}
variable "directory_password" {
  description = "Password for directory admin user"
  default = null
  type = string
  sensitive = true
}
variable "directory_size" {
  description = "Size of the directory (Small or Large)"
  default = null
  type = string
}
variable "enable_internet_access" {
  description = "Enable internet access for WorkSpaces"
  default = null
  type = bool
}
variable "default_ou" {
  description = "Default organizational unit for WorkSpaces"
  default = null
  type = string
}
variable "bundle_id" {
  description = "WorkSpaces bundle ID"
  default = null
  type = string
}
variable "user_name" {
  description = "Username for WorkSpace"
  default = null
  type = string
}
variable "workspace_properties" {
  description = "WorkSpace properties configuration"
  default = null
  type = object({
    compute_type_name                         = optional(string)
    user_volume_size_gib                     = optional(number)
    root_volume_size_gib                     = optional(number)
    running_mode                             = optional(string)
    running_mode_auto_stop_timeout_in_minutes = optional(number)
  })
}

# -------- Computed values from YAML or variables ----------
locals {
  prefix                  = coalesce(var.prefix, local.config_file.prefix, "workspaces")
  region                  = coalesce(var.region, local.config_file.region, "us-west-2")
  vpc_cidr               = coalesce(var.vpc_cidr, local.config_file.vpc_cidr, "10.70.0.0/16")
  subnet_a_cidr          = coalesce(var.subnet_a_cidr, local.config_file.subnet_a_cidr, "10.70.1.0/24")
  subnet_b_cidr          = coalesce(var.subnet_b_cidr, local.config_file.subnet_b_cidr, "10.70.2.0/24")
  directory_name         = coalesce(var.directory_name, local.config_file.directory_name, "workspaces.local")
  directory_password     = coalesce(var.directory_password, local.config_file.directory_password)
  directory_size         = coalesce(var.directory_size, local.config_file.directory_size, "Small")
  enable_internet_access = coalesce(var.enable_internet_access, local.config_file.enable_internet_access, true)
  default_ou             = var.default_ou != null ? var.default_ou : (local.config_file.default_ou != null ? local.config_file.default_ou : "")
  bundle_id              = coalesce(var.bundle_id, local.config_file.bundle_id)
  user_name              = coalesce(var.user_name, local.config_file.user_name)
  workspace_properties   = var.workspace_properties != null ? var.workspace_properties : coalesce(local.config_file.workspace_properties, {})
}

# ----------------- Data Sources -----------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_workspaces_bundle" "value_windows_10" {
  bundle_id = local.bundle_id
}

# ----------------- VPC and Networking -----------------
resource "aws_vpc" "workspaces_vpc" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.prefix}-vpc"
  }
}

resource "aws_subnet" "workspaces_subnet_a" {
  vpc_id            = aws_vpc.workspaces_vpc.id
  cidr_block        = local.subnet_a_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.prefix}-subnet-a"
  }
}

resource "aws_subnet" "workspaces_subnet_b" {
  vpc_id            = aws_vpc.workspaces_vpc.id
  cidr_block        = local.subnet_b_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${local.prefix}-subnet-b"
  }
}

resource "aws_internet_gateway" "workspaces_igw" {
  count  = local.enable_internet_access ? 1 : 0
  vpc_id = aws_vpc.workspaces_vpc.id

  tags = {
    Name = "${local.prefix}-igw"
  }
}

resource "aws_route_table" "workspaces_rt" {
  count  = local.enable_internet_access ? 1 : 0
  vpc_id = aws_vpc.workspaces_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.workspaces_igw[0].id
  }

  tags = {
    Name = "${local.prefix}-rt"
  }
}

resource "aws_route_table_association" "workspaces_rta_a" {
  count          = local.enable_internet_access ? 1 : 0
  subnet_id      = aws_subnet.workspaces_subnet_a.id
  route_table_id = aws_route_table.workspaces_rt[0].id
}

resource "aws_route_table_association" "workspaces_rta_b" {
  count          = local.enable_internet_access ? 1 : 0
  subnet_id      = aws_subnet.workspaces_subnet_b.id
  route_table_id = aws_route_table.workspaces_rt[0].id
}

# ----------------- WorkSpaces Directory -----------------
resource "aws_directory_service_directory" "workspaces_directory" {
  name     = local.directory_name
  password = local.directory_password
  size     = local.directory_size
  type     = "SimpleAD"

  vpc_settings {
    vpc_id     = aws_vpc.workspaces_vpc.id
    subnet_ids = [aws_subnet.workspaces_subnet_a.id, aws_subnet.workspaces_subnet_b.id]
  }

  tags = {
    Name = "${local.prefix}-directory"
  }
}

# ----------------- WorkSpaces Directory Registration -----------------
resource "aws_workspaces_directory" "workspaces_directory" {
  directory_id = aws_directory_service_directory.workspaces_directory.id

  subnet_ids = [aws_subnet.workspaces_subnet_a.id, aws_subnet.workspaces_subnet_b.id]

  tags = {
    Name = "${local.prefix}-workspaces-directory"
  }

  self_service_permissions {
    change_compute_type  = true
    increase_volume_size = true
    rebuild_workspace    = true
    restart_workspace    = true
    switch_running_mode  = true
  }

  workspace_access_properties {
    device_type_android    = "ALLOW"
    device_type_chromeos   = "ALLOW"
    device_type_ios        = "ALLOW"
    device_type_linux      = "ALLOW"
    device_type_osx        = "ALLOW"
    device_type_web        = "ALLOW"
    device_type_windows    = "ALLOW"
    device_type_zeroclient = "ALLOW"
  }

  workspace_creation_properties {
    custom_security_group_id            = aws_security_group.workspaces_sg.id
    default_ou                          = local.default_ou
    enable_internet_access              = local.enable_internet_access
    enable_maintenance_mode             = true
    user_enabled_as_local_administrator = true
  }
}

# ----------------- Security Group -----------------
resource "aws_security_group" "workspaces_sg" {
  name_prefix = "${local.prefix}-workspaces-"
  vpc_id      = aws_vpc.workspaces_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.prefix}-workspaces-sg"
  }
}

# ----------------- WorkSpace -----------------
resource "aws_workspaces_workspace" "workspace" {
  count = local.user_name != null ? 1 : 0
  
  directory_id = aws_workspaces_directory.workspaces_directory.id
  bundle_id    = local.bundle_id
  user_name    = local.user_name

  root_volume_encryption_enabled = true
  user_volume_encryption_enabled = true

  dynamic "workspace_properties" {
    for_each = local.workspace_properties != null ? [local.workspace_properties] : []
    content {
      compute_type_name                         = workspace_properties.value.compute_type_name
      user_volume_size_gib                     = workspace_properties.value.user_volume_size_gib
      root_volume_size_gib                     = workspace_properties.value.root_volume_size_gib
      running_mode                             = workspace_properties.value.running_mode
      running_mode_auto_stop_timeout_in_minutes = workspace_properties.value.running_mode_auto_stop_timeout_in_minutes
    }
  }

  tags = {
    Name = "${local.prefix}-workspace-${local.user_name}"
  }
}

# --------------- Outputs ---------------
output "directory_id" {
  value = aws_directory_service_directory.workspaces_directory.id
}

output "directory_dns_ip_addresses" {
  value = aws_directory_service_directory.workspaces_directory.dns_ip_addresses
}

output "workspaces_directory_id" {
  value = aws_workspaces_directory.workspaces_directory.id
}

output "workspaces_directory_registration_code" {
  value = aws_workspaces_directory.workspaces_directory.registration_code
}

output "workspace_id" {
  value = length(aws_workspaces_workspace.workspace) > 0 ? aws_workspaces_workspace.workspace[0].id : null
}

output "workspace_ip_address" {
  value = length(aws_workspaces_workspace.workspace) > 0 ? aws_workspaces_workspace.workspace[0].ip_address : null
}

output "workspace_computer_name" {
  value = length(aws_workspaces_workspace.workspace) > 0 ? aws_workspaces_workspace.workspace[0].computer_name : null
}

output "workspace_state" {
  value = length(aws_workspaces_workspace.workspace) > 0 ? aws_workspaces_workspace.workspace[0].state : null
}

output "vpc_id" {
  value = aws_vpc.workspaces_vpc.id
}

output "subnet_ids" {
  value = [aws_subnet.workspaces_subnet_a.id, aws_subnet.workspaces_subnet_b.id]
}

output "security_group_id" {
  value = aws_security_group.workspaces_sg.id
}

# Connection information
output "workspace_connection_info" {
  value = length(aws_workspaces_workspace.workspace) > 0 ? {
    registration_code = aws_workspaces_directory.workspaces_directory.registration_code
    workspace_id      = aws_workspaces_workspace.workspace[0].id
    computer_name     = aws_workspaces_workspace.workspace[0].computer_name
    ip_address        = aws_workspaces_workspace.workspace[0].ip_address
  } : null
  description = "WorkSpace connection information"
}