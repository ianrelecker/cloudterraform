terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.113" }
  }
  
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatecloudterraform"
    container_name       = "tfstate"
    key                  = "linux-a1v2-vm.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# -------- Vars (override via -var or tfvars) ----------
variable "prefix"            { default = "linux-a1v2" }
variable "location"          { default = "westus" }
variable "vm_size"           { default = "Standard_A1_v2" }
variable "admin_username"    { default = "azureuser" }
variable "github_username"   { 
  description = "GitHub username to fetch SSH public keys from"
  type        = string
}
variable "vnet_cidr"         { default = "10.60.0.0/16" }
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

locals {
  all_keys = split("\n", trimspace(data.http.github_ssh_keys.response_body))
  valid_keys = [for key in local.all_keys : key if length(trimspace(key)) > 0 && can(regex("^ssh-rsa", key))]
  selected_key = length(local.valid_keys) > 0 ? local.valid_keys[0] : ""
}

# ----------------- Network -----------------
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_cidr]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "ssh-in"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = [var.allowed_ssh_cidr]
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_public_ip" "pip" {
  count               = var.create_public_ip ? 1 : 0
  name                = "${var.prefix}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  name                = "${var.prefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.create_public_ip ? azurerm_public_ip.pip[0].id : null
  }
}

# ----------------- VM -----------------
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "${var.prefix}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [azurerm_network_interface.nic.id]

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    name                 = "${var.prefix}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.selected_key
  }

  custom_data = base64encode(file("${path.module}/cloud-init.yaml"))
}

# --------------- Output ---------------
output "private_ip" { value = azurerm_network_interface.nic.private_ip_address }
output "public_ip"  { value = var.create_public_ip ? azurerm_public_ip.pip[0].ip_address : null }