#!/bin/bash
# scripts/setup-ansible-vault.sh
# Initialize Ansible Vault for credential management

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Ansible Vault Setup${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

cd "$PROJECT_ROOT"

# Check if vault file already encrypted
VAULT_FILE="inventory/group_vars/all/vault.yml"

if ansible-vault view "$VAULT_FILE" &>/dev/null; then
    echo -e "${YELLOW}Vault file is already encrypted${NC}"
    echo ""
    echo "To edit: ansible-vault edit $VAULT_FILE"
    echo "To view: ansible-vault view $VAULT_FILE"
    exit 0
fi

# Encrypt vault file
echo -e "${YELLOW}Encrypting vault file: $VAULT_FILE${NC}"
echo ""
echo "You will be prompted to create a vault password."
echo "This password will be required to run the playbooks."
echo ""

ansible-vault encrypt "$VAULT_FILE"

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Vault file encrypted successfully${NC}"
    echo ""
    echo "IMPORTANT: Before running playbooks, edit the vault and set real credentials:"
    echo "  ansible-vault edit $VAULT_FILE"
    echo ""
    echo "To avoid typing password each time, create ~/.ansible-vault-pass:"
    echo "  echo 'your-vault-password' > ~/.ansible-vault-pass"
    echo "  chmod 600 ~/.ansible-vault-pass"
    echo ""
    echo "Then use: --vault-password-file ~/.ansible-vault-pass"
else
    echo -e "${RED}Failed to encrypt vault file${NC}"
    exit 1
fi
