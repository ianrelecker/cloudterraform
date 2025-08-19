terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.113" }
    http    = { source = "hashicorp/http",    version = ">= 3.4.0" }
  }

  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatecloudterraform"
    container_name       = "tfstate"
    key                  = "ollama-h100-vmss.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# ---------------- Vars -----------------
variable "prefix"             { default = "ollama-h100" }
variable "location"           { default = "eastus" }
variable "zone"               { default = "1" }
variable "vm_size"            { default = "Standard_ND96isr_H100_v5" }
variable "instance_count"     { default = 1 }
variable "admin_username"     { default = "azureuser" }
variable "github_username" {
  description = "GitHub username to fetch SSH public keys from"
  type        = string
}
variable "vnet_cidr"          { default = "10.90.0.0/16" }
variable "subnet_cidr"        { default = "10.90.1.0/24" }
variable "allowed_ssh_cidr"   { default = "0.0.0.0/0" }
variable "model_disk_size_gb" { default = 1024 }

# ---------------- Data -----------------
data "http" "github_ssh_keys" {
  url = "https://github.com/${var.github_username}.keys"
  request_headers = {
    Accept = "text/plain"
  }
}

locals {
  all_keys     = split("\n", trimspace(data.http.github_ssh_keys.response_body))
  valid_keys   = [for key in local.all_keys : key if length(trimspace(key)) > 0 && can(regex("^ssh-", key))]
  selected_key = length(local.valid_keys) > 0 ? local.valid_keys[0] : ""
}

# --------------- Network ---------------
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
    name                       = "ssh-in-vnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = [var.vnet_cidr]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ollama-vnet-in"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "11434"
    source_address_prefixes    = [var.vnet_cidr]
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# --------------- Private LB ---------------
resource "azurerm_lb" "lb" {
  name                = "${var.prefix}-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "PrivateFrontend"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    private_ip_address_version    = "IPv4"
  }
}

resource "azurerm_lb_backend_address_pool" "bepool" {
  name            = "${var.prefix}-bepool"
  loadbalancer_id = azurerm_lb.lb.id
}

resource "azurerm_lb_probe" "probe" {
  name            = "${var.prefix}-probe-11434"
  loadbalancer_id = azurerm_lb.lb.id
  port            = 11434
  protocol        = "Tcp"
}

resource "azurerm_lb_rule" "ollama" {
  name                           = "${var.prefix}-rule-11434"
  loadbalancer_id                = azurerm_lb.lb.id
  protocol                       = "Tcp"
  frontend_ip_configuration_name = "PrivateFrontend"
  frontend_port                  = 11434
  backend_port                   = 11434
  disable_outbound_snat          = false
  enable_floating_ip             = false
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bepool.id]
  probe_id                       = azurerm_lb_probe.probe.id
}

# Allow LB health probe source
resource "azurerm_network_security_rule" "lb_probe" {
  name                        = "${var.prefix}-lb-probe-allow"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "11434"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

# NAT Gateway for outbound Internet egress
resource "azurerm_public_ip" "nat_pip" {
  name                = "${var.prefix}-nat-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "nat" {
  name                = "${var.prefix}-nat"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Standard"
  public_ip_address_ids = [azurerm_public_ip.nat_pip.id]
}

resource "azurerm_subnet_nat_gateway_association" "nat_assoc" {
  subnet_id      = azurerm_subnet.subnet.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

# --------------- VM Scale Set ---------------
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "${var.prefix}-vmss"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = var.vm_size
  instances           = var.instance_count
  admin_username      = var.admin_username
  upgrade_mode        = "Manual"
  zones               = [var.zone]

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  data_disk {
    lun                  = 0
    caching              = "ReadOnly"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.model_disk_size_gb
    create_option        = "Empty"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.selected_key
  }

  network_interface {
    name    = "${var.prefix}-nic"
    primary = true

    ip_configuration {
      name                                   = "${var.prefix}-ipcfg"
      primary                                = true
      subnet_id                               = azurerm_subnet.subnet.id
      load_balancer_backend_address_pool_ids  = [azurerm_lb_backend_address_pool.bepool.id]
    }
  }

  custom_data = base64encode(file("${path.module}/cloud-init.yaml"))
}

# --------------- Outputs ---------------
output "lb_private_ip" {
  value       = azurerm_lb.lb.frontend_ip_configuration[0].private_ip_address
  description = "Private IP address of the Load Balancer (port 11434)."
}

output "resource_group" {
  value = azurerm_resource_group.rg.name
}
