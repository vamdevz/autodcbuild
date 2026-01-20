#!/bin/bash
# scripts/validate-dc-health.sh
# Standalone script to validate DC health without full deployment

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Validate arguments
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 ENVIRONMENT TARGET_HOST"
    echo ""
    echo "Examples:"
    echo "  $0 staging stg-dc01.staging.linkedin.biz"
    echo "  $0 production lva1-dc03.linkedin.biz"
    exit 1
fi

ENVIRONMENT=$1
TARGET_HOST=$2

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}DC HEALTH VALIDATION${NC}"
echo -e "${GREEN}============================================${NC}"
echo "Environment: $ENVIRONMENT"
echo "Target: $TARGET_HOST"
echo ""

# Run only health check roles
ansible-playbook playbooks/master-pipeline.yml \
    -i "inventory/$ENVIRONMENT/hosts.yml" \
    --limit "$TARGET_HOST" \
    --tags "health-check,dns-check,auth-check" \
    --ask-vault-pass

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Health validation complete${NC}"
else
    echo ""
    echo -e "${RED}❌ Health validation failed${NC}"
    exit 1
fi
