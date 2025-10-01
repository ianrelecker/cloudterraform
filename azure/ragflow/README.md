# Azure RAGFlow Single VM

Provision a single Ubuntu 22.04 VM that installs [RAGFlow](https://github.com/infiniflow/ragflow) with the full Docker
image (includes embedding models) and an Ollama service with pre-pulled models. The install runs through cloud-init on
first boot.

## Usage

```bash
tfenv install 1.6.0
terraform init
terraform apply \
  -var "github_username=YOUR_GITHUB_HANDLE" \
  -var "ollama_models=[\"llama3:8b\",\"mistral:7b\"]"
```

Terraform will prompt for `github_username` if not supplied and uses the first public **ssh-rsa** key on that account,
which Azure requires for VM provisioning. By default, the deployment:

- Opens ports 22 (SSH), 80 (RAGFlow UI) and 11434 (Ollama API).
- Uses VM size `Standard_NC4as_T4_v3` and a 128 GB OS disk.
- Clones the `main` branch of the RAGFlow repo, switches Docker to `infiniflow/ragflow:v0.20.5`, and brings the stack
  up via `docker compose`.
- Installs Ollama, binds it to `0.0.0.0`, and downloads the configured models.

Outputs include the public IP, RAGFlow URL, and Ollama endpoint.
