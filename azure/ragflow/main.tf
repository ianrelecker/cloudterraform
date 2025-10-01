terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.113" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    http    = { source = "hashicorp/http", version = "~> 3.4" }
  }

  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatecloudterraform"
    container_name       = "tfstate"
    key                  = "azure-ragflow.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# -------- Vars (override via -var or tfvars) ----------
variable "prefix" { default = "ragflow" }
variable "location" { default = "westus" }
variable "vm_size" { default = "Standard_NC4as_T4_v3" }
variable "admin_username" { default = "azureuser" }

variable "github_username" {
  description = "GitHub username to fetch SSH public keys from"
  type        = string
}

variable "vnet_cidr" { default = "10.72.0.0/16" }
variable "subnet_cidr" { default = "10.72.1.0/24" }

variable "allowed_ssh_cidr" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "allowed_http_cidr" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "allowed_ollama_cidr" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "ragflow_branch" { default = "main" }
variable "ragflow_image" { default = "infiniflow/ragflow:v0.20.5" }
variable "ollama_models" {
  type    = list(string)
  default = ["llama3:8b"]
}
variable "os_disk_size_gb" { default = 128 }

# ----------------- SSH key selection -----------------
data "http" "github_keys" {
  url             = "https://github.com/${var.github_username}.keys"
  request_headers = { Accept = "text/plain" }
}

locals {
  github_keys_raw = split("\n", trimspace(data.http.github_keys.response_body))

  # Azure currently only accepts ssh-rsa keys for VM creation.
  github_valid_keys = [
    for key in local.github_keys_raw : trimspace(key)
    if length(trimspace(key)) > 0 && can(regex("^ssh-rsa", trimspace(key)))
  ]

  selected_ssh_key = length(local.github_valid_keys) > 0 ? local.github_valid_keys[0] : ""
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  suffix      = random_string.suffix.result
  rg_name     = "${var.prefix}-${local.suffix}-rg"
  vnet_name   = "${var.prefix}-${local.suffix}-vnet"
  subnet_name = "${var.prefix}-${local.suffix}-subnet"
  nsg_name    = "${var.prefix}-${local.suffix}-nsg"
  pip_name    = "${var.prefix}-${local.suffix}-pip"
  nic_name    = "${var.prefix}-${local.suffix}-nic"
  vm_name     = "${var.prefix}-${local.suffix}-vm"
  osdisk_name = "${var.prefix}-${local.suffix}-osdisk"
}

# ----------------- Network -----------------
resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "subnet" {
  name                 = local.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_cidr]
}

resource "azurerm_network_security_group" "nsg" {
  name                = local.nsg_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_ssh_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ragflow-http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = var.allowed_http_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "pip" {
  name                = local.pip_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  name                = local.nic_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ----------------- VM -----------------
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = local.vm_name
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.nic.id]

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    name                 = local.osdisk_name
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.selected_ssh_key
  }

  identity { type = "SystemAssigned" }

  custom_data = base64encode(
    templatefile(
      "${path.module}/cloud-init.yaml",
      {
        admin_username = var.admin_username
        ragflow_branch = var.ragflow_branch
        ragflow_image  = var.ragflow_image
        ollama_models  = var.ollama_models
      }
    )
  )

  tags = {
    workload = "ragflow"
    managed  = "terraform"
  }

  lifecycle {
    ignore_changes = [custom_data]
    precondition {
      condition     = local.selected_ssh_key != ""
      error_message = "Ensure the GitHub account exposes at least one ssh-rsa public key (Azure requires RSA)."
    }
  }
}

# --------------- Outputs ---------------
output "resource_group" { value = azurerm_resource_group.rg.name }
output "ragflow_public_ip" { value = azurerm_public_ip.pip.ip_address }
output "ragflow_url" { value = "http://${azurerm_public_ip.pip.ip_address}" }
output "ollama_endpoint" { value = "http://${azurerm_public_ip.pip.ip_address}:11434" }
output "vm_id" { value = azurerm_linux_virtual_machine.vm.id }
