#!/bin/bash
# scripts/run-dc-promotion.sh
# Execute DC promotion pipeline with environment selection

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
ENVIRONMENT=""
TARGET_HOST=""
CHECK_MODE=false
VAULT_PASSWORD_FILE=""

# Display usage
usage() {
    cat << EOF
Usage: $0 -e ENVIRONMENT -t TARGET_HOST [OPTIONS]

Required Arguments:
  -e, --environment ENV     Environment to deploy (staging|production)
  -t, --target HOST         Target hostname to promote

Optional Arguments:
  -c, --check               Run in check mode (dry-run)
  -v, --vault-password FILE Path to vault password file
  -h, --help                Show this help message

Examples:
  # Promote staging DC
  $0 -e staging -t stg-dc01.staging.linkedin.biz

  # Dry-run production deployment
  $0 -e production -t lva1-dc03.linkedin.biz --check

  # Use vault password file
  $0 -e production -t lva1-dc03.linkedin.biz -v ~/.ansible-vault-pass

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -t|--target)
            TARGET_HOST="$2"
            shift 2
            ;;
        -c|--check)
            CHECK_MODE=true
            shift
            ;;
        -v|--vault-password)
            VAULT_PASSWORD_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$ENVIRONMENT" ]] || [[ -z "$TARGET_HOST" ]]; then
    echo -e "${RED}ERROR: Environment and target host are required${NC}"
    usage
fi

# Validate environment
if [[ "$ENVIRONMENT" != "staging" ]] && [[ "$ENVIRONMENT" != "production" ]]; then
    echo -e "${RED}ERROR: Environment must be 'staging' or 'production'${NC}"
    exit 1
fi

# Production confirmation
if [[ "$ENVIRONMENT" == "production" ]] && [[ "$CHECK_MODE" == false ]]; then
    echo -e "${YELLOW}⚠️  WARNING: You are about to promote a PRODUCTION domain controller!${NC}"
    echo -e "${YELLOW}Target: $TARGET_HOST${NC}"
    echo ""
    read -p "Type 'PROMOTE' to continue: " confirmation
    
    if [[ "$confirmation" != "PROMOTE" ]]; then
        echo -e "${RED}Aborted by user${NC}"
        exit 1
    fi
fi

# Build ansible-playbook command
cd "$PROJECT_ROOT"

ANSIBLE_CMD="ansible-playbook playbooks/master-pipeline.yml"
ANSIBLE_CMD="$ANSIBLE_CMD -i inventory/$ENVIRONMENT/hosts.yml"
ANSIBLE_CMD="$ANSIBLE_CMD --limit $TARGET_HOST"

if [[ "$CHECK_MODE" == true ]]; then
    ANSIBLE_CMD="$ANSIBLE_CMD --check"
    echo -e "${YELLOW}Running in CHECK MODE (dry-run)${NC}"
fi

if [[ -n "$VAULT_PASSWORD_FILE" ]]; then
    ANSIBLE_CMD="$ANSIBLE_CMD --vault-password-file $VAULT_PASSWORD_FILE"
else
    ANSIBLE_CMD="$ANSIBLE_CMD --ask-vault-pass"
fi

# Display execution plan
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}DC PROMOTION PIPELINE${NC}"
echo -e "${GREEN}============================================${NC}"
echo "Environment: $ENVIRONMENT"
echo "Target Host: $TARGET_HOST"
echo "Check Mode: $CHECK_MODE"
echo "Project Root: $PROJECT_ROOT"
echo ""
echo -e "${GREEN}Executing:${NC} $ANSIBLE_CMD"
echo ""

# Execute playbook
eval "$ANSIBLE_CMD"

# Completion message
if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}✅ DEPLOYMENT COMPLETE${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo "Server: $TARGET_HOST"
    echo "Environment: $ENVIRONMENT"
    echo ""
    echo "Next steps:"
    echo "1. Verify certificate: go/incerts"
    echo "2. Confirm FIM compliance with InfoSec SPM team"
    echo "3. Update change ticket"
    echo "4. Monitor agent initialization (5-10 minutes)"
    echo ""
else
    echo ""
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}❌ DEPLOYMENT FAILED${NC}"
    echo -e "${RED}============================================${NC}"
    echo "Check logs above for errors"
    exit 1
fi
