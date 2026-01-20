#!/bin/bash
# Test connectivity to lab DCs (DC01 and DC02)

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Testing Lab DC Connectivity (DC01 & DC02)                          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

cd "$PROJECT_ROOT"

# Test DC01
echo -e "${YELLOW}Testing DC01 (4.234.159.63)...${NC}"
echo -e "${BLUE}  1. Network connectivity (WinRM port 5985)${NC}"
if nc -zv -w 5 4.234.159.63 5985 2>&1 | grep -q "succeeded\|Connected"; then
    echo -e "     ${GREEN}✓${NC} Port 5985 accessible"
else
    echo -e "     ${RED}✗${NC} Port 5985 not accessible"
fi

echo -e "${BLUE}  2. LDAPS connectivity (port 636)${NC}"
if nc -zv -w 5 4.234.159.63 636 2>&1 | grep -q "succeeded\|Connected"; then
    echo -e "     ${GREEN}✓${NC} Port 636 accessible"
else
    echo -e "     ${RED}✗${NC} Port 636 not accessible"
fi

echo ""

# Test DC02
echo -e "${YELLOW}Testing DC02 (20.108.4.144)...${NC}"
echo -e "${BLUE}  1. Network connectivity (WinRM port 5985)${NC}"
if nc -zv -w 5 20.108.4.144 5985 2>&1 | grep -q "succeeded\|Connected"; then
    echo -e "     ${GREEN}✓${NC} Port 5985 accessible"
else
    echo -e "     ${RED}✗${NC} Port 5985 not accessible"
    echo -e "     ${YELLOW}Note: DC02 might need WinRM enabled${NC}"
fi

echo -e "${BLUE}  2. RDP connectivity (port 3389)${NC}"
if nc -zv -w 5 20.108.4.144 3389 2>&1 | grep -q "succeeded\|Connected"; then
    echo -e "     ${GREEN}✓${NC} Port 3389 accessible"
else
    echo -e "     ${RED}✗${NC} Port 3389 not accessible"
fi

echo ""
echo -e "${YELLOW}Testing Ansible connectivity...${NC}"

# Check if ansible is installed
if ! command -v ansible &> /dev/null; then
    echo -e "${RED}✗ Ansible not installed${NC}"
    echo -e "${YELLOW}Install with: pip3 install ansible pywinrm${NC}"
    exit 1
fi

echo -e "${BLUE}  Running ansible ping against lab DCs...${NC}"
echo ""

# Test with ansible (will prompt for vault password)
ansible lab_domain -i inventory/lab/hosts.yml -m win_ping --ask-vault-pass || {
    echo ""
    echo -e "${YELLOW}If connection failed, check:${NC}"
    echo -e "  1. VMs are running (use start-dc01.sh or az vm start)"
    echo -e "  2. Vault passwords are correct (ansible-vault edit inventory/group_vars/all/vault.yml)"
    echo -e "  3. WinRM is enabled on the VMs"
    echo -e "  4. NSG rules allow port 5985"
}

echo ""
echo -e "${GREEN}✓ Connectivity test complete${NC}"
