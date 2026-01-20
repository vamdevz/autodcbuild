#!/bin/bash
# test-pipeline-syntax.sh - Validate all Ansible files

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Validating Ansible Pipeline..."
echo ""

# Check syntax of master pipeline
echo -n "Checking master-pipeline.yml... "
if ansible-playbook playbooks/master-pipeline.yml --syntax-check &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Check all role task files
for role in roles/*/tasks/main.yml; do
    role_name=$(echo $role | cut -d'/' -f2)
    echo -n "Checking role: $role_name... "
    
    # Create temp playbook to test role
    cat > /tmp/test-role.yml << EOF
---
- hosts: localhost
  gather_facts: no
  roles:
    - $role_name
EOF
    
    if ansible-playbook /tmp/test-role.yml --syntax-check &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        exit 1
    fi
done

# Check inventory files
for inv in inventory/*/hosts.yml; then
    inv_name=$(basename $(dirname $inv))
    echo -n "Checking inventory: $inv_name... "
    
    if ansible-inventory -i $inv --list &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        exit 1
    fi
done

echo ""
echo -e "${GREEN}All validation checks passed!${NC}"
