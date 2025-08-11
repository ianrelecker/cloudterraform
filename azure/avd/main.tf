terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.113" }
    azuread = { source = "hashicorp/azuread", version = "~> 2.0" }
  }
  
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatecloudterraform"
    container_name       = "tfstate"
    key                  = "avd-landing-zone.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

# -------- Load config from YAML ----------
locals {
  config_file = fileexists("${path.module}/avd-config.yaml") ? yamldecode(file("${path.module}/avd-config.yaml")) : {
    prefix = null
    location = null
    resource_group_name = null
    vnet_address_space = null
    subnet_address_prefixes = null
    host_pool_name = null
    host_pool_type = null
    host_pool_load_balancer_type = null
    host_pool_max_sessions = null
    workspace_name = null
    application_group_name = null
    vm_count = null
    vm_size = null
    admin_username = null
    admin_password = null
    domain_name = null
    domain_user = null
    domain_password = null
    ou_path = null
    vm_image = null
    create_fslogix_storage = null
    storage_sku = null
    log_analytics_workspace_name = null
    recovery_vault_name = null
  }
}

# -------- Vars (override via -var or tfvars) ----------
variable "prefix" { 
  default = null
  type = string
}
variable "location" { 
  default = null
  type = string
}
variable "resource_group_name" {
  description = "Name of the resource group"
  default = null
  type = string
}
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  default = null
  type = list(string)
}
variable "subnet_address_prefixes" {
  description = "Address prefixes for AVD subnet"
  default = null
  type = list(string)
}
variable "host_pool_name" {
  description = "Name of the host pool"
  default = null
  type = string
}
variable "host_pool_type" {
  description = "Host pool type (Personal or Pooled)"
  default = null
  type = string
}
variable "host_pool_load_balancer_type" {
  description = "Load balancer type (BreadthFirst, DepthFirst, Persistent)"
  default = null
  type = string
}
variable "host_pool_max_sessions" {
  description = "Maximum sessions per host"
  default = null
  type = number
}
variable "workspace_name" {
  description = "Name of the workspace"
  default = null
  type = string
}
variable "application_group_name" {
  description = "Name of the application group"
  default = null
  type = string
}
variable "vm_count" {
  description = "Number of session host VMs"
  default = null
  type = number
}
variable "vm_size" {
  description = "Size of the session host VMs"
  default = null
  type = string
}
variable "admin_username" {
  description = "Local admin username for VMs"
  default = null
  type = string
}
variable "admin_password" {
  description = "Local admin password for VMs"
  default = null
  type = string
  sensitive = true
}
variable "domain_name" {
  description = "Domain name for AD join"
  default = null
  type = string
}
variable "domain_user" {
  description = "Domain user for AD join"
  default = null
  type = string
}
variable "domain_password" {
  description = "Domain password for AD join"
  default = null
  type = string
  sensitive = true
}
variable "ou_path" {
  description = "OU path for domain joined machines"
  default = null
  type = string
}
variable "vm_image" {
  description = "VM image configuration"
  default = null
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}
variable "create_fslogix_storage" {
  description = "Create FSLogix storage account"
  default = null
  type = bool
}
variable "storage_sku" {
  description = "SKU for storage accounts"
  default = null
  type = string
}
variable "log_analytics_workspace_name" {
  description = "Name of Log Analytics workspace"
  default = null
  type = string
}
variable "recovery_vault_name" {
  description = "Name of Recovery Services vault"
  default = null
  type = string
}

# -------- Computed values from YAML or variables ----------
locals {
  prefix                      = coalesce(var.prefix, local.config_file.prefix, "avd")
  location                    = coalesce(var.location, local.config_file.location, "East US")
  resource_group_name         = coalesce(var.resource_group_name, local.config_file.resource_group_name, "${local.prefix}-rg")
  vnet_address_space         = coalesce(var.vnet_address_space, local.config_file.vnet_address_space, ["10.80.0.0/16"])
  subnet_address_prefixes     = coalesce(var.subnet_address_prefixes, local.config_file.subnet_address_prefixes, ["10.80.1.0/24"])
  host_pool_name             = coalesce(var.host_pool_name, local.config_file.host_pool_name, "${local.prefix}-hostpool")
  host_pool_type             = coalesce(var.host_pool_type, local.config_file.host_pool_type, "Pooled")
  host_pool_load_balancer_type = coalesce(var.host_pool_load_balancer_type, local.config_file.host_pool_load_balancer_type, "BreadthFirst")
  host_pool_max_sessions     = coalesce(var.host_pool_max_sessions, local.config_file.host_pool_max_sessions, 10)
  workspace_name             = coalesce(var.workspace_name, local.config_file.workspace_name, "${local.prefix}-workspace")
  application_group_name     = coalesce(var.application_group_name, local.config_file.application_group_name, "${local.prefix}-appgroup")
  vm_count                   = coalesce(var.vm_count, local.config_file.vm_count, 2)
  vm_size                    = coalesce(var.vm_size, local.config_file.vm_size, "Standard_D4s_v3")
  admin_username             = coalesce(var.admin_username, local.config_file.admin_username, "avdadmin")
  admin_password             = coalesce(var.admin_password, local.config_file.admin_password)
  domain_name                = coalesce(var.domain_name, local.config_file.domain_name)
  domain_user                = coalesce(var.domain_user, local.config_file.domain_user)
  domain_password            = coalesce(var.domain_password, local.config_file.domain_password)
  ou_path                    = var.ou_path != null ? var.ou_path : (local.config_file.ou_path != null ? local.config_file.ou_path : "")
  vm_image                   = var.vm_image != null ? var.vm_image : coalesce(local.config_file.vm_image, {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-11"
    sku       = "win11-22h2-avd"
    version   = "latest"
  })
  create_fslogix_storage     = coalesce(var.create_fslogix_storage, local.config_file.create_fslogix_storage, true)
  storage_sku                = coalesce(var.storage_sku, local.config_file.storage_sku, "Standard_LRS")
  log_analytics_workspace_name = coalesce(var.log_analytics_workspace_name, local.config_file.log_analytics_workspace_name, "${local.prefix}-law")
  recovery_vault_name        = coalesce(var.recovery_vault_name, local.config_file.recovery_vault_name, "${local.prefix}-vault")
}

# Generate random strings for unique naming
resource "random_string" "avd_token" {
  length  = 16
  special = true
}

resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}

# ----------------- Resource Group -----------------
resource "azurerm_resource_group" "avd" {
  name     = local.resource_group_name
  location = local.location

  tags = {
    Environment = "Production"
    Purpose     = "Azure Virtual Desktop"
    Terraform   = "true"
  }
}

# ----------------- Virtual Network -----------------
resource "azurerm_virtual_network" "avd" {
  name                = "${local.prefix}-vnet"
  address_space       = local.vnet_address_space
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name

  tags = azurerm_resource_group.avd.tags
}

resource "azurerm_subnet" "avd" {
  name                 = "${local.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.avd.name
  virtual_network_name = azurerm_virtual_network.avd.name
  address_prefixes     = local.subnet_address_prefixes
}

# ----------------- Network Security Group -----------------
resource "azurerm_network_security_group" "avd" {
  name                = "${local.prefix}-nsg"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name

  security_rule {
    name                       = "RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AVD_Agent"
    priority                   = 1002
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "WindowsVirtualDesktop"
  }

  tags = azurerm_resource_group.avd.tags
}

resource "azurerm_subnet_network_security_group_association" "avd" {
  subnet_id                 = azurerm_subnet.avd.id
  network_security_group_id = azurerm_network_security_group.avd.id
}

# ----------------- Log Analytics Workspace -----------------
resource "azurerm_log_analytics_workspace" "avd" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = azurerm_resource_group.avd.tags
}

# ----------------- Recovery Services Vault -----------------
resource "azurerm_recovery_services_vault" "avd" {
  name                = local.recovery_vault_name
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name
  sku                 = "Standard"
  soft_delete_enabled = true

  tags = azurerm_resource_group.avd.tags
}

# ----------------- Storage Account for FSLogix -----------------
resource "azurerm_storage_account" "fslogix" {
  count                    = local.create_fslogix_storage ? 1 : 0
  name                     = "${replace(local.prefix, "-", "")}fslogix${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.avd.name
  location                 = azurerm_resource_group.avd.location
  account_tier             = "Premium"
  account_replication_type = "LRS"
  account_kind             = "FileStorage"

  azure_files_authentication {
    directory_type = "AADDS"
  }

  tags = azurerm_resource_group.avd.tags
}

resource "azurerm_storage_share" "fslogix" {
  count                = local.create_fslogix_storage ? 1 : 0
  name                 = "fslogix"
  storage_account_name = azurerm_storage_account.fslogix[0].name
  quota                = 100
  enabled_protocol     = "SMB"
  access_tier          = "Premium"
}

# ----------------- AVD Host Pool -----------------
resource "azurerm_virtual_desktop_host_pool" "avd" {
  name                = local.host_pool_name
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name

  type                             = local.host_pool_type
  load_balancer_type               = local.host_pool_load_balancer_type
  maximum_sessions_allowed         = local.host_pool_max_sessions
  start_vm_on_connect              = true
  custom_rdp_properties           = "audiocapturemode:i:1;audiomode:i:0;drivestoredirect:s:*;redirectclipboard:i:1;redirectcomports:i:1;redirectprinters:i:1;redirectsmartcards:i:1;screen mode id:i:2;"
  friendly_name                    = "${local.prefix} Host Pool"
  description                      = "Host pool for ${local.prefix} AVD deployment"
  validate_environment             = false
  preferred_app_group_type         = "Desktop"


  tags = azurerm_resource_group.avd.tags
}

# ----------------- AVD Host Pool Registration Token -----------------
resource "azurerm_virtual_desktop_host_pool_registration_info" "avd" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.avd.id
  expiration_date = timeadd(timestamp(), "48h")
}

# ----------------- AVD Application Group -----------------
resource "azurerm_virtual_desktop_application_group" "avd" {
  name                = local.application_group_name
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name

  type                 = "Desktop"
  host_pool_id         = azurerm_virtual_desktop_host_pool.avd.id
  friendly_name        = "${local.prefix} Application Group"
  description          = "Application group for ${local.prefix} AVD deployment"

  tags = azurerm_resource_group.avd.tags
}

# ----------------- AVD Workspace -----------------
resource "azurerm_virtual_desktop_workspace" "avd" {
  name                = local.workspace_name
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name

  friendly_name = "${local.prefix} Workspace"
  description   = "Workspace for ${local.prefix} AVD deployment"

  tags = azurerm_resource_group.avd.tags
}

# ----------------- Associate Application Group to Workspace -----------------
resource "azurerm_virtual_desktop_workspace_application_group_association" "avd" {
  workspace_id         = azurerm_virtual_desktop_workspace.avd.id
  application_group_id = azurerm_virtual_desktop_application_group.avd.id
}

# ----------------- Session Host VMs -----------------
resource "azurerm_network_interface" "session_host" {
  count               = local.vm_count
  name                = "${local.prefix}-sh-${count.index + 1}-nic"
  location            = azurerm_resource_group.avd.location
  resource_group_name = azurerm_resource_group.avd.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.avd.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = azurerm_resource_group.avd.tags
}

resource "azurerm_windows_virtual_machine" "session_host" {
  count               = local.vm_count
  name                = "${local.prefix}-sh-${count.index + 1}"
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location
  size                = local.vm_size
  admin_username      = local.admin_username
  admin_password      = local.admin_password

  network_interface_ids = [
    azurerm_network_interface.session_host[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = local.vm_image.publisher
    offer     = local.vm_image.offer
    sku       = local.vm_image.sku
    version   = local.vm_image.version
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(azurerm_resource_group.avd.tags, {
    Role = "SessionHost"
  })
}

# ----------------- Domain Join Extension (if domain specified) -----------------
resource "azurerm_virtual_machine_extension" "domain_join" {
  count                = local.domain_name != null ? local.vm_count : 0
  name                 = "join-domain"
  virtual_machine_id   = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "JsonADDomainExtension"
  type_handler_version = "1.3"

  settings = jsonencode({
    Name    = local.domain_name
    OUPath  = local.ou_path
    User    = "${local.domain_name}\\${local.domain_user}"
    Restart = "true"
    Options = "3"
  })

  protected_settings = jsonencode({
    Password = local.domain_password
  })

  depends_on = [azurerm_windows_virtual_machine.session_host]
}

# ----------------- AVD Agent Extension -----------------
resource "azurerm_virtual_machine_extension" "avd_agent" {
  count                = local.vm_count
  name                 = "Microsoft.PowerShell.DSC"
  virtual_machine_id   = azurerm_windows_virtual_machine.session_host[count.index].id
  publisher            = "Microsoft.Powershell"
  type                 = "DSC"
  type_handler_version = "2.73"
  depends_on           = [azurerm_virtual_machine_extension.domain_join]

  settings = jsonencode({
    ModulesUrl = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_09-08-2022.zip"
    ConfigurationFunction = "Configuration.ps1\\AddSessionHost"
    Properties = {
      hostPoolName          = azurerm_virtual_desktop_host_pool.avd.name
      registrationInfoToken = azurerm_virtual_desktop_host_pool_registration_info.avd.token
      aadJoin               = local.domain_name == null ? true : false
    }
  })
}

# --------------- Outputs ---------------
output "resource_group_name" {
  value = azurerm_resource_group.avd.name
}

output "host_pool_id" {
  value = azurerm_virtual_desktop_host_pool.avd.id
}

output "host_pool_name" {
  value = azurerm_virtual_desktop_host_pool.avd.name
}

output "application_group_id" {
  value = azurerm_virtual_desktop_application_group.avd.id
}

output "workspace_id" {
  value = azurerm_virtual_desktop_workspace.avd.id
}

output "workspace_name" {
  value = azurerm_virtual_desktop_workspace.avd.name
}

output "session_host_names" {
  value = [for vm in azurerm_windows_virtual_machine.session_host : vm.name]
}

output "session_host_private_ips" {
  value = [for nic in azurerm_network_interface.session_host : nic.ip_configuration[0].private_ip_address]
}

output "fslogix_storage_account" {
  value = local.create_fslogix_storage ? azurerm_storage_account.fslogix[0].name : null
}

output "fslogix_share_url" {
  value = local.create_fslogix_storage ? "\\\\${azurerm_storage_account.fslogix[0].name}.file.core.windows.net\\${azurerm_storage_share.fslogix[0].name}" : null
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.avd.id
}

output "recovery_vault_id" {
  value = azurerm_recovery_services_vault.avd.id
}

output "vnet_id" {
  value = azurerm_virtual_network.avd.id
}

output "subnet_id" {
  value = azurerm_subnet.avd.id
}

output "registration_token" {
  value     = azurerm_virtual_desktop_host_pool_registration_info.avd.token
  sensitive = true
}

# Connection information
output "avd_connection_info" {
  value = {
    workspace_name    = azurerm_virtual_desktop_workspace.avd.name
    host_pool_name    = azurerm_virtual_desktop_host_pool.avd.name
    resource_group    = azurerm_resource_group.avd.name
    session_host_count = local.vm_count
    web_client_url    = "https://rdweb.wvd.microsoft.com/arm/webclient"
  }
  description = "AVD connection and management information"
}