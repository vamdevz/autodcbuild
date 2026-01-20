# LinkedIn Domain Controller IaaC Build Pipeline

**Enterprise automation for Domain Controller promotion**

---

## Project Overview

This repository contains an enterprise-grade automation pipeline for promoting Windows Servers to Domain Controllers, supporting both linkedin.biz and internal.linkedin.cn domains.

## Current Implementation

### Production Pipeline
**Location**: [`v2-github-actions/`](v2-github-actions/)

Modern CI/CD pipeline using GitHub Actions + PowerShell with Azure integration:

- **Technology**: GitHub Actions, PowerShell, Azure Key Vault
- **Execution Time**: 30-50 minutes
- **Deployment**: Self-service via GitHub UI or CLI
- **Security**: Azure Key Vault with OIDC, no static secrets
- **Validation**: Automated PR checks
- **Audit**: Complete trail in GitHub + Azure Monitor

📖 **[View Documentation →](v2-github-actions/README.md)**

### Legacy Implementation  
**Location**: [`v1-ansible/`](v1-ansible/)

Original implementation using Ansible for automation:

- **Technology**: Ansible, Python, WinRM
- **Status**: Production tested, stable, maintained
- **Use Case**: Fallback option or for teams preferring Ansible

📖 **[View Documentation →](v1-ansible/README.md)**

---

## Quick Start

### Option 1: GitHub Actions Pipeline (Recommended)

```bash
cd v2-github-actions

# Deploy to staging
gh workflow run deploy-staging.yml -f target_dc=stg-dc01

# Deploy to production (requires approval)
gh workflow run deploy-prod.yml -f target_dc=lva1-dc03 -f change_ticket=CHG0012345
```

### Option 2: Traditional Ansible

```bash
cd v1-ansible
./scripts/run-dc-promotion.sh -e staging -t stg-dc01.staging.linkedin.biz
```

---

## What's Automated

Both implementations provide complete automation for:

1. ✅ **Pre-promotion validation** - Domain, DNS, disk space, connectivity
2. ✅ **DC Promotion** - Role installation, dcpromo execution  
3. ✅ **Reboot handling** - Automatic restart and service monitoring
4. ✅ **Health checks** - 7 comprehensive tests (dcdiag, repadmin, etc.)
5. ✅ **DNS configuration** - 4 conditional forwarders
6. ✅ **Authentication validation** - Event log monitoring
7. ✅ **Agent installation** - 5 security agents + .NET 4.8
8. ✅ **Post-configuration** - LDAPS group, certificates, reporting

**Average Duration**: 30-80 minutes (fully unattended)

---

## Target Environments

Both implementations support:
- **Domains**: linkedin.biz, internal.linkedin.cn
- **Platform**: Windows Server 2019/2022
- **Environments**: Lab, Staging, Production
- **Locations**: Multi-datacenter (global)

---

## Security Features

- Encrypted credential storage (Azure Key Vault or Ansible Vault)
- Authentication via OIDC or Kerberos
- Production approval gates
- Complete audit logging
- Change ticket validation
- Least-privilege access

---

## Documentation

### GitHub Actions Pipeline
- [Quick Start & Features](v2-github-actions/README.md)
- [Azure Setup (Key Vault, OIDC)](v2-github-actions/docs/AZURE-SETUP.md)
- [GitHub Actions Setup (Runners)](v2-github-actions/docs/GITHUB-ACTIONS-SETUP.md)

### Ansible Pipeline
- [Quick Start Guide](v1-ansible/PIPELINE-QUICKSTART.md)
- [Complete Architecture](v1-ansible/DC-BUILD-PROMOTION-PROJECT.md)
- [Implementation Summary](v1-ansible/PROJECT-COMPLETE-SUMMARY.md)

### General
- [Version History](CHANGELOG.md)

---

## Support

- **AD Operations**: ad-ops@linkedin.com
- **Automation**: infra-automation@linkedin.com  
- **Security**: infosec-spm@linkedin.com

---

**Recommended**: Use GitHub Actions pipeline ([v2-github-actions/](v2-github-actions/)) for new deployments  
**Last Updated**: 2026-01-17
