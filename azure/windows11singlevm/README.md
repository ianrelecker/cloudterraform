# Azure Windows 11 Single VM (Terraform)

This module provisions a single Windows 11 Pro VM on Azure with a basic network stack and public RDP access, following the repo’s single-VM module style.

## What It Creates
- Resource group, virtual network, subnet
- Network security group with inbound TCP 3389 (RDP)
- Optional public IP (enabled by default)
- NIC and Windows 11 VM
- VM extension that runs `setup.ps1` for initial configuration

## Public RDP Access
- NSG opens `TCP/3389` to `allowed_rdp_cidr` (default `0.0.0.0/0`).
- Public IP is created by default (`create_public_ip = true`).
- `setup.ps1` enables RDP and opens the Windows Firewall.

Security note: Exposing RDP publicly increases risk. Restrict `allowed_rdp_cidr` to trusted IPs and consider Azure Bastion, a VPN, or just-in-time (JIT) access.

## Files
- `main.tf` — Terraform for network + VM
- `setup.ps1` — PowerShell setup executed via RunCommand

## Variables
- `prefix` (string, default `win11-d2s`)
- `location` (string, default `westus`)
- `vm_size` (string, default `Standard_D2s_v6`)
- `admin_username` (string, default `azureuser`)
- `admin_password` (string, required, sensitive)
- `vnet_cidr` (string, default `10.71.0.0/16`)
- `subnet_cidr` (string, default `10.71.1.0/24`)
- `allowed_rdp_cidr` (string, default `0.0.0.0/0`)
- `create_public_ip` (bool, default `true`)

## Outputs
- `private_ip` — Private NIC IP
- `public_ip` — Public IP address (if created)

## Usage
1. Change directory:
   ```
   cd azure/windows11singlevm
   ```
2. Create a `terraform.tfvars` with a strong password:
   ```hcl
   admin_password   = "Your$trongP@ssw0rd!"
   # allowed_rdp_cidr = "203.0.113.0/24"   # optional hardening
   ```
3. Init/plan/apply:
   ```
   terraform init
   terraform plan
   terraform apply
   ```
4. RDP to the `public_ip` output using `admin_username`/`admin_password`.

## Image Details
- Publisher: `MicrosoftWindowsDesktop`
- Offer: `Windows-11`
- SKU: `win11-23h2-pro` (latest)
 - Generation: Gen2 (required for Dsv6; enforced by Trusted Launch)

## What `setup.ps1` Does
- Enables Remote Desktop by setting `fDenyTSConnections = 0`.
- Ensures Windows Firewall allows inbound `TCP/3389`.
- Attempts `winget source update` if winget is available.
- Logs a completion event to the Application event log.

You can extend `setup.ps1` to install software or apply policies.

## Security
- Trusted Launch enabled by default:
  - `security_type = "TrustedLaunch"`
  - `secure_boot_enabled = true`
  - `vtpm_enabled = true`
  Ensure your chosen VM size/region supports Trusted Launch.
