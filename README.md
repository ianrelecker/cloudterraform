# Cloud Terraform Templates

A collection of simple, reusable Terraform configurations for spinning up VMs and infrastructure across different cloud providers. Perfect for quick testing, development environments, or learning cloud infrastructure.

## What's Inside

This repo contains ready-to-use Terraform templates for:

### AWS
- **Linux Single VM** (`aws/linuxsinglevm/`) - Basic Ubuntu server with Docker pre-installed

### Azure  
- **Linux Single VM** (`azure/linuxsinglevm/`) - Basic Ubuntu server setup
- **Ollama VMs** (`azure/OllamaSingleVM/`) - GPU-enabled VMs for running Ollama AI models
  - A10 variant for high-performance workloads
  - T4 variant for cost-effective AI inference
- **VPN Gateway** (`azure/Networking/vpngatewayv1/`) - Site-to-site VPN setup

## Quick Start

### Prerequisites
- [Terraform](https://www.terraform.io/downloads.html) installed
- Cloud provider CLI tools configured:
  - AWS: `aws configure` 
  - Azure: `az login`
- Your GitHub username (for SSH key setup)

### For AWS

1. **Set up the backend** (one-time setup):
   ```bash
   # Create S3 bucket for Terraform state
   aws s3api create-bucket --bucket terraform-state-cloudterraform --region us-west-2
   
   # Enable versioning (recommended)
   aws s3api put-bucket-versioning --bucket terraform-state-cloudterraform --versioning-configuration Status=Enabled
   ```

2. **Deploy a VM**:
   ```bash
   cd aws/linuxsinglevm
   terraform init
   terraform plan
   terraform apply
   ```

3. **Connect**:
   ```bash
   ssh ubuntu@<public_ip_from_output>
   ```

### For Azure

1. **Set up the backend** (one-time setup):
   ```bash
   # Create resource group and storage account
   az group create --name terraform-state-rg --location westus
   az storage account create --name tfstatecloudterraform --resource-group terraform-state-rg --location westus --sku Standard_LRS
   az storage container create --name tfstate --account-name tfstatecloudterraform
   ```

2. **Deploy a VM**:
   ```bash
   cd azure/linuxsinglevm
   terraform init
   terraform plan 
   terraform apply
   ```

3. **Connect**:
   ```bash
   ssh azureuser@<public_ip_from_output>
   ```

## How It Works

### SSH Key Management
All templates automatically fetch your SSH public keys from GitHub (`https://github.com/YOUR_USERNAME.keys`) and configure them for passwordless SSH access. No need to manually manage key pairs!

### Cloud-init Configuration
Each VM comes with a `cloud-init.yaml` file that:
- Updates the system packages
- Installs common tools (curl, wget, git, vim, htop, etc.)
- Sets up Docker (where specified)
- Logs setup completion

### Networking
- **AWS**: Creates a VPC, subnet, internet gateway, and security group
- **Azure**: Creates a virtual network, subnet, and network security group
- SSH access is allowed from anywhere by default (customize with `allowed_ssh_cidr`)

## Customization

Each template supports common variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `github_username` | Your GitHub username for SSH keys | **Required** |
| `prefix` | Resource name prefix | varies by template |
| `region`/`location` | Cloud region | `us-west-2` / `westus` |
| `instance_type`/`vm_size` | VM size | `t3.micro` / `Standard_A1_v2` |
| `allowed_ssh_cidr` | IP range for SSH access | `0.0.0.0/0` |
| `create_public_ip` | Whether to assign public IP | `true` |

### Example with Custom Variables
```bash
terraform apply \
  -var="github_username=myusername" \
  -var="prefix=dev-test" \
  -var="instance_type=t3.small" \
  -var="allowed_ssh_cidr=203.0.113.0/24"
```

## Special Configurations

### Ollama GPU VMs (Azure)
The Ollama templates create GPU-enabled VMs perfect for running AI models:
- **A10 variant**: High-performance GPU for demanding workloads
- **T4 variant**: Cost-effective GPU for inference and lighter workloads

Both come pre-configured with GPU drivers and Ollama installation scripts.

Default VM sizes are chosen for cost-effectiveness:
- AWS: `t3.micro` (eligible for free tier)
- Azure: `Standard_A1_v2` (low-cost option)

## Security Notes

- SSH access is open to `0.0.0.0/0` by default - restrict this for production use
- No secrets are stored in this repo - SSH keys are fetched from GitHub
- All sensitive Terraform state is stored in cloud backends, not locally

## Troubleshooting

### Common Issues

**"Backend configuration changed"**
```bash
terraform init -reconfigure
```

**"No SSH keys found"**  
Make sure your GitHub profile has public SSH keys uploaded.

**"Resource already exists"**  
Change the `prefix` variable to use unique resource names.

**Permission errors**  
Ensure your cloud CLI is configured with appropriate permissions for creating VMs, networks, and storage.

## Contributing

Feel free to add new cloud providers or configurations! Follow the existing pattern:
- Each configuration gets its own directory
- Include both `main.tf` and `cloud-init.yaml`
- Use consistent variable naming
- Update this README

## License

MIT License - use these templates however you'd like!