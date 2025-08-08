terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.113" }
  }
  
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatecloudterraform"
    container_name       = "tfstate"
    key                  = "ollama-vm.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# -------- Vars (override via -var or tfvars) ----------
variable "prefix"            { default = "ollama" }
variable "location"          { default = "westus3" } # change to your region
variable "zone"              { default = "1" }
variable "vm_size"           { default = "Standard_NV36ads_A10_v5" } # full A10
variable "admin_username"    { default = "azureuser" }
variable "github_username"   { 
  description = "GitHub username to fetch SSH public keys from"
  type        = string
}
variable "vnet_cidr"         { default = "10.20.0.0/16" }
variable "subnet_cidr"       { default = "10.20.1.0/24" }
variable "allowed_ssh_cidr"  { default = "0.0.0.0/0" } # tighten to your IP
variable "create_public_ip"  { default = false }
variable "model_disk_size_gb"{ default = 512 }
variable "disk_iops"         { default = 3000 } # Premium SSD v2 perf knobs
variable "disk_mbps"         { default = 125 }

# ----------------- Data Sources -----------------
data "http" "github_ssh_keys" {
  url = "https://github.com/${var.github_username}.keys"
  request_headers = {
    Accept = "text/plain"
  }
}

# Parse and filter SSH keys to get only RSA keys
locals {
  all_keys = split("\n", trimspace(data.http.github_ssh_keys.response_body))
  rsa_keys = [for key in local.all_keys : key if startswith(key, "ssh-rsa")]
  selected_rsa_key = length(local.rsa_keys) > 0 ? local.rsa_keys[0] : ""
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

# ----------------- Data disk for models (Premium SSD v2) -----------------
resource "azurerm_managed_disk" "models" {
  name                 = "${var.prefix}-models-disk"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = "PremiumV2_LRS"
  disk_size_gb         = var.model_disk_size_gb
  disk_iops_read_write = var.disk_iops
  disk_mbps_read_write = var.disk_mbps
  zone                 = var.zone
  create_option        = "Empty"
}

# ----------------- VM -----------------
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "${var.prefix}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  zone                = var.zone
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [azurerm_network_interface.nic.id]

  # Ubuntu 22.04 LTS Gen2
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    name                 = "${var.prefix}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  # Note: security_profile not supported in azurerm_linux_virtual_machine
  # For GPU driver compatibility, use disable_password_authentication = false if needed

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.selected_rsa_key
  }

  custom_data = base64encode(file("${path.module}/cloud-init.yaml"))
}

resource "azurerm_virtual_machine_data_disk_attachment" "attach" {
  managed_disk_id    = azurerm_managed_disk.models.id
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  lun                = 0
  caching            = "ReadOnly"
}

# NVIDIA GPU driver (Linux) – installs vGPU/CUDA driver on A10
resource "azurerm_virtual_machine_extension" "nvidia" {
  name                 = "NvidiaGpuDriverLinux"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm.id
  publisher            = "Microsoft.HpcCompute"
  type                 = "NvidiaGpuDriverLinux"
  type_handler_version = "1.11"
  auto_upgrade_minor_version = true

  # Optional: pin a specific driver branch if latest causes CUDA issues on A10s
  # settings = jsonencode({ driverVersion = "535.161" })
}

# --------------- Output ---------------
output "private_ip" { value = azurerm_network_interface.nic.private_ip_address }
output "public_ip"  { value = var.create_public_ip ? azurerm_public_ip.pip[0].ip_address : null }
