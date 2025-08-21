# Multi Cloud Terraform Templates

A collection of simple, reusable Terraform configurations for spinning up VMs and infrastructure across different cloud providers. Perfect for quick testing, development environments, or learning cloud infrastructure.

## What's Inside

Ready-to-use Terraform templates organized by provider. Each module has its own README with details and usage.

### AWS
- [`aws/linuxsinglevm/`](aws/linuxsinglevm/): Basic Ubuntu server with Docker pre-installed
- [`aws/kendra/`](aws/kendra/): Kendra index with S3 data source for document search
- [`aws/lambda/s3processor/`](aws/lambda/s3processor/): Serverless PDF size reducer (S3 + Lambda + API Gateway)
- [`aws/lambda/s3pdfrepair/`](aws/lambda/s3pdfrepair/): Serverless PDF repair/normalization (S3 + Lambda + API Gateway)
- [`aws/ses-smtp/`](aws/ses-smtp/): SES SMTP setup for sending email
- [`aws/sns/`](aws/sns/): SNS topic + optional IAM user for Grafana SMS alerts
- [`aws/workspaces/`](aws/workspaces/): AWS WorkSpaces provisioning

### Azure
- [`azure/linuxsinglevm/`](azure/linuxsinglevm/): Basic Ubuntu server setup
- [`azure/OllamaSingleVM/`](azure/OllamaSingleVM/): GPU-enabled VMs for running Ollama AI models
  - `ollamaT4vm`: Cost-effective inference
  - `ollamaA10vm`: Balanced performance
  - `ollamaA100vm`: Highest performance (single GPU)
  - `ollamaH100vm`: Latest-gen high-performance GPU
- [`azure/OllamaLBVM/`](azure/OllamaLBVM/): Private load-balanced Ollama via VM Scale Sets
  - `T4`: Cost-effective GPU VMSS behind an internal load balancer
  - `H100`: High-performance GPU VMSS behind an internal load balancer
- [`azure/Networking/vpngatewayv1/`](azure/Networking/vpngatewayv1/): Site-to-site VPN gateway
- [`azure/cve-processor/`](azure/cve-processor/): Automated CVE ingestion + SOC analysis (Functions + SQL + Web)

## Repo Structure

- `aws/`: AWS-focused modules (compute, serverless, productivity)
- `azure/`: Azure-focused modules (compute, networking, AI/GPU, app stacks)
- `LICENSE`: MIT license
- `README.md`: This overview

## Quick Start

### Prerequisites
- Terraform installed
- Cloud provider CLI tools configured as needed:
  - AWS: `aws configure`
  - Azure: `az login`
- Your GitHub username (for SSH key setup in VM templates)
- Module-specific tools may be required (e.g., Azure Functions Core Tools for `azure/cve-processor`)

### For AWS

1. **Set up the backend** (one-time setup, optional if module overrides):
   ```bash
   # Create S3 bucket for Terraform state
   aws s3api create-bucket --bucket terraform-state-cloudterraform --region us-west-2
   
   # Enable versioning (recommended)
   aws s3api put-bucket-versioning --bucket terraform-state-cloudterraform --versioning-configuration Status=Enabled
   ```

2. **Deploy a VM** (provide your GitHub username):
  ```bash
  cd aws/linuxsinglevm
  terraform init
  terraform plan
   terraform apply -var="github_username=<your_github_username>"
  ```

3. **Connect**:
   ```bash
   ssh ubuntu@<public_ip_from_output>
   ```

### For Azure

1. **Set up the backend** (one-time setup, optional if module overrides):
   ```bash
   # Create resource group and storage account
   az group create --name terraform-state-rg --location westus
   az storage account create --name tfstatecloudterraform --resource-group terraform-state-rg --location westus --sku Standard_LRS
   az storage container create --name tfstate --account-name tfstatecloudterraform
   ```

2. **Deploy a VM** (provide your GitHub username):
  ```bash
  cd azure/linuxsinglevm
  terraform init
  terraform plan 
   terraform apply -var="github_username=<your_github_username>"
  ```

3. **Connect**:
   ```bash
   ssh azureuser@<public_ip_from_output>
   ```

## How It Works

### SSH Key Management
VM templates can fetch your SSH public keys from GitHub (`https://github.com/YOUR_USERNAME.keys`) and configure them for passwordless SSH access. No need to manually manage key pairs for these modules.

### Cloud-init Configuration
Each VM comes with a `cloud-init.yaml` file that:
- Updates the system packages
- Installs common tools (curl, wget, git, vim, htop, etc.)
- Sets up Docker (where specified)
- Logs setup completion

### Networking
- **AWS**: Creates a VPC, subnet, internet gateway, and security group
- **Azure**: Creates a virtual network, subnet, and network security group
- SSH access is open by default in some templates; restrict via `allowed_ssh_cidr` for non-dev use

## Customization

Many templates support common variables:

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
GPU-enabled VM templates for running Ollama models:
- T4: Cost-effective GPU for inference and lighter workloads
- A10: Balanced performance for demanding workloads
- A100: Highest performance (single GPU) and cost
- H100: Latest-gen highest performance workloads

All variants include GPU drivers and Ollama installation scripts.

Default VM sizes are chosen for cost-effectiveness (override as needed):
- AWS: `t3.micro` (often free-tier eligible)
- Azure: `Standard_A1_v2` (low-cost option)

### Ollama LB VM Scale Sets (Azure)
For scaling Ollama behind a private load balancer within a VNet:
- Uses a Standard internal Load Balancer on port `11434` for traffic.
- Deploys a VM Scale Set (VMSS) with GPU instances and attaches a large data disk for models.
- NSG allows intra-VNet access; expose via VPN, Private Endpoint, or application gateway as needed.

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

### Module-Specific Notes
- Some modules (e.g., `aws/lambda/s3processor`, `aws/lambda/s3pdfrepair`) require editing a YAML config file before deployment.
- VM modules expect a valid `github_username` so your public SSH keys can be fetched automatically.

## Contributing

Feel free to add new cloud providers or configurations! Follow the existing pattern:
- Each configuration gets its own directory
- Include both `main.tf` and `cloud-init.yaml` where applicable
- Use consistent variable naming
- Add a module-specific README and update this one’s “What’s Inside”

Note: Some modules (like the serverless PDF tools) read settings from their YAML config files in each directory. Update values such as `bucket_name` to a globally unique value before `terraform apply`.

## License

MIT License - use these templates however you'd like!

## Cost Estimates (Infracost)

This repo includes Infracost to estimate Terraform costs per service locally and in PRs via GitHub Actions.

- Add a repo secret `INFRACOST_API_KEY` containing your Infracost API key.
- PRs that touch Terraform files trigger a cost diff comment across all services.
- Locally, estimate costs per service directory with the helper script.

### Local Usage

1) Install Terraform (>= 1.6) and the Infracost CLI.
2) Authenticate:
   `infracost configure set api_key <YOUR_KEY>`
3) Estimate a service:
   `scripts/infracost_service.sh aws/kendra`
   Use `--diff` for a branch vs default comparison:
   `scripts/infracost_service.sh azure/linuxsinglevm --diff`

Notes:
- Some services need variables. Minimal tfvars live in `.infracost/vars/` and are auto-applied by the script and CI.
- The tooling initializes Terraform with `-backend=false` to avoid touching remote state backends during cost estimation.
