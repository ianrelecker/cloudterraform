terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.113" }
  }

  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatecloudterraform"
    container_name       = "tfstate"
    key                  = "windows-d2s-vm.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# -------- Vars (override via -var or tfvars) ----------
variable "prefix"            { default = "windows-d2s" }
variable "location"          { default = "westus" }
variable "vm_size"           { default = "Standard_D2s_v6" }
variable "admin_username"    { default = "azureuser" }
variable "admin_password" {
  description = "Admin password for Windows VM (must meet Azure complexity requirements)"
  type        = string
  sensitive   = true
}
variable "vnet_cidr"         { default = "10.70.0.0/16" }
variable "subnet_cidr"       { default = "10.70.1.0/24" }
variable "allowed_rdp_cidr"  { default = "0.0.0.0/0" }
variable "create_public_ip"  { default = true }

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
    name                       = "rdp-in"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefixes    = [var.allowed_rdp_cidr]
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
resource "azurerm_windows_virtual_machine" "vm" {
  name                = "${var.prefix}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [azurerm_network_interface.nic.id]

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"    # Gen2 Desktop Experience
    version   = "latest"
  }

  os_disk {
    name                 = "${var.prefix}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  enable_automatic_updates = true
}

# Optional: Run initial setup via RunCommand (PowerShell)
resource "azurerm_virtual_machine_extension" "run_setup" {
  name                       = "${var.prefix}-runsetup"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm.id
  publisher                  = "Microsoft.CPlat.Core"
  type                       = "RunCommandWindows"
  type_handler_version       = "1.1"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandId = "RunPowerShellScript"
    script    = [file("${path.module}/setup.ps1")]
  })
}

# --------------- Output ---------------
output "private_ip" { value = azurerm_network_interface.nic.private_ip_address }
output "public_ip"  { value = var.create_public_ip ? azurerm_public_ip.pip[0].ip_address : null }
