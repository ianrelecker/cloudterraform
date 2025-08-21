#!/usr/bin/env bash
set -euo pipefail

# Estimate cost for a single Terraform service directory.
# Usage: scripts/infracost_service.sh <service-dir> [--diff]
# Examples:
#   scripts/infracost_service.sh aws/kendra
#   scripts/infracost_service.sh azure/linuxsinglevm --diff

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <service-dir> [--diff]" >&2
  exit 1
fi

SERVICE_DIR=$1
# Normalize leading ./ for pattern matching and output
SERVICE_DIR=${SERVICE_DIR#./}
MODE=${2:-breakdown}

if [[ ! -d "$SERVICE_DIR" ]]; then
  echo "Directory not found: $SERVICE_DIR" >&2
  exit 1
fi

# Choose tfvars if required by the service
TFVARS=""
case "$SERVICE_DIR" in
  aws/kendra* )
    TFVARS=".infracost/vars/aws-kendra.tfvars" ;;
  azure/linuxsinglevm*|azure/OllamaSingleVM/*|azure/OllamaLBVM/* )
    TFVARS=".infracost/vars/azure-github-username.tfvars" ;;
  * )
    TFVARS="" ;;
esac

echo "[Infracost] Service: $SERVICE_DIR"
if [[ -n "$TFVARS" ]]; then
  echo "[Infracost] Using tfvars: $TFVARS"
  TFVARS_FLAG=(--terraform-var-file "$TFVARS")
else
  TFVARS_FLAG=()
fi

# Ensure Terraform init without remote backend
pushd "$SERVICE_DIR" >/dev/null
terraform init -backend=false -input=false -no-color >/dev/null
popd >/dev/null

if [[ "$MODE" == "--diff" ]]; then
  infracost diff --path "$SERVICE_DIR" ${TFVARS_FLAG[@]+"${TFVARS_FLAG[@]}"}
else
  infracost breakdown --path "$SERVICE_DIR" ${TFVARS_FLAG[@]+"${TFVARS_FLAG[@]}"}
fi
