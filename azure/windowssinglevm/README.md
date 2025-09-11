# Azure Windows Single VM (Terraform)

This module provisions a single Windows Server (Desktop Experience) VM on Azure with a basic network stack and RDP access, mirroring the structure of the Linux single VM module.

## What It Creates
- Resource group, virtual network, subnet
- Network security group with inbound TCP 3389 (RDP)
- Optional public IP (enabled by default)
- Network interface
- Windows Server 2022 Datacenter (Desktop, Gen2) VM
- A VM extension that runs `setup.ps1` for initial configuration

## Public RDP Access
- NSG opens `TCP/3389` to the CIDR in `allowed_rdp_cidr` (default `0.0.0.0/0`).
- The VM has a public IP by default (`create_public_ip = true`).
- The `setup.ps1` script also enables RDP and ensures the Windows Firewall allows it.

Security note: Exposing RDP publicly increases risk. Restrict `allowed_rdp_cidr` to trusted IPs and consider Azure Bastion, a VPN, or just-in-time (JIT) access.

## Files
- `main.tf` — Terraform resources and variables
- `setup.ps1` — PowerShell script executed via RunCommand extension

Windows on Azure does not use cloud-init YAML (that’s used by Linux). For initial configuration, this module uses a PowerShell script.

## Variables
- `prefix` (string, default `windows-d2s`)
- `location` (string, default `westus`)
- `vm_size` (string, default `Standard_D2s_v6`)
- `admin_username` (string, default `azureuser`)
- `admin_password` (string, required, sensitive)
- `vnet_cidr` (string, default `10.70.0.0/16`)
- `subnet_cidr` (string, default `10.70.1.0/24`)
- `allowed_rdp_cidr` (string, default `0.0.0.0/0`)
- `create_public_ip` (bool, default `true`)

## Outputs
- `private_ip` — Private IP of the NIC
- `public_ip` — Public IP address (if created)

## Usage
1. Change directory:
   ```
   cd azure/windowssinglevm
   ```
2. Create a `terraform.tfvars` with a strong password:
   ```hcl
   admin_password   = "Your$trongP@ssw0rd!"
   # Optional hardening: restrict RDP
   # allowed_rdp_cidr = "203.0.113.0/24"
   ```
3. Init/plan/apply:
   ```
   terraform init
   terraform plan
   terraform apply
   ```
4. Connect via RDP to the `public_ip` output with `admin_username`/`admin_password`.

## What `setup.ps1` Does
- Enables Remote Desktop by setting `fDenyTSConnections = 0`.
- Ensures Windows Firewall allows inbound `TCP/3389`:
  - Enables the built-in "Remote Desktop" firewall group, or
  - Adds an explicit rule for port 3389 as a fallback.
- Attempts `winget source update` if winget is available.
- Logs a completion event to the Windows Application event log.

You can customize `setup.ps1` to add software installs (e.g., via winget or Chocolatey) or additional configuration steps.

## Image Details
- Publisher: `MicrosoftWindowsServer`
- Offer: `WindowsServer`
- SKU: `2022-datacenter-g2` (Gen2 required for Dsv6)
