# LinkedIn DC Promotion Pipeline

**Automated CI/CD pipeline for Domain Controller promotion using GitHub Actions + PowerShell**

## Overview

Enterprise-grade automation pipeline for promoting Windows Servers to Domain Controllers in Azure environments. Built for reliability, security, and ease of use with GitHub Actions integration and Azure Key Vault.

### Key Features

- ✅ **Fully Automated**: Complete end-to-end DC promotion workflow
- ✅ **Azure Native**: Key Vault integration with OIDC authentication
- ✅ **Self-Service**: Deploy via GitHub Actions UI or CLI
- ✅ **Validated**: Automated PR checks before deployment
- ✅ **Secure**: No static secrets, managed identities, complete audit trail
- ✅ **Fast**: Optimized execution (30-50 minutes average)
- ✅ **Reliable**: Comprehensive health validation at each stage

## Quick Start

### Prerequisites

1. Azure subscription with Key Vault access
2. GitHub repository with Actions enabled
3. Self-hosted runner in Azure VNet
4. Domain admin credentials in Key Vault

### First Time Setup

```bash
# 1. Clone repository
git clone YOUR_REPO
cd v2-github-actions

# 2. Start with LAB environment (recommended)
# See: docs/LAB-SETUP.md

# 3. Configure Azure
# See: docs/AZURE-SETUP.md

# 4. Deploy self-hosted runner
# See: docs/GITHUB-ACTIONS-SETUP.md

# 5. Update configuration
# Edit config/lab.json, config/staging.json, and config/production.json
```

### Deploy to Lab (Testing)

**Via GitHub UI:**
1. Go to Actions → "Deploy to Lab"
2. Click "Run workflow"
3. Enter target DC: `dc01.linkedin.local`
4. Click "Run workflow"

**Via GitHub CLI:**
```bash
gh workflow run deploy-lab.yml -f target_dc=dc01.linkedin.local
```

📖 **[Complete Lab Setup Guide →](docs/LAB-SETUP.md)**

### Deploy to Staging

**Via GitHub UI:**
1. Go to Actions → "Deploy to Staging"
2. Click "Run workflow"
3. Enter target DC hostname
4. Click "Run workflow"

**Via GitHub CLI:**
```bash
gh workflow run deploy-staging.yml -f target_dc=stg-dc01.staging.linkedin.biz
```

### Deploy to Production

**Via GitHub UI:**
1. Go to Actions → "Deploy to Production"
2. Click "Run workflow"
3. Enter target DC and change ticket
4. Approve deployment (if required reviewers configured)
5. Monitor execution

**Via GitHub CLI:**
```bash
gh workflow run deploy-prod.yml \
  -f target_dc=lva1-dc03.linkedin.biz \
  -f change_ticket=CHG0012345
```

## Architecture

```
┌─────────────────┐
│  GitHub Actions │
│   (Orchestration)│
└────────┬────────┘
         │
         ├─→ Pre-Checks (PowerShell Module)
         │   ├─ Domain membership
         │   ├─ DNS configuration
         │   ├─ DC connectivity
         │   ├─ Disk space
         │   └─ AD module
         │
         ├─→ DC Promotion (PowerShell Module)
         │   ├─ Install AD DS role
         │   ├─ Promote to DC
         │   ├─ Reboot handling
         │   └─ Health validation (7 tests)
         │
         └─→ Post-Configuration (PowerShell Module)
             ├─ DNS forwarders (4 zones)
             ├─ Authentication validation
             ├─ Agent installation (5 agents)
             ├─ LDAPS group membership
             ├─ Certificate enrollment
             └─ Comprehensive reporting
```

## Project Structure

```
v2-github-actions/
├── .github/workflows/         # GitHub Actions workflows
│   ├── validate.yml          # PR validation
│   ├── deploy-staging.yml    # Staging deployment
│   └── deploy-prod.yml       # Production deployment
├── scripts/
│   ├── Invoke-DCPromotionPipeline.ps1  # Main orchestrator
│   └── modules/              # PowerShell modules
│       ├── PrePromotionChecks.psm1
│       ├── DCPromotion.psm1
│       └── PostConfiguration.psm1
├── config/                   # Environment configurations
│   ├── staging.json
│   ├── production.json
│   └── azure-keyvault.json
├── tests/                    # Pester tests
│   └── PrePromotionChecks.Tests.ps1
└── docs/                     # Documentation
    ├── AZURE-SETUP.md
    └── GITHUB-ACTIONS-SETUP.md
```

## What's Automated

All 8 stages of DC promotion are fully automated:

### 1. Pre-Promotion Validation (5 checks)
- Domain membership verification
- DNS configuration check
- DC connectivity test (LDAP port 389)
- Disk space validation (D: and E: drives)
- AD PowerShell module availability

### 2. DC Promotion
- AD DS role installation
- Domain Controller promotion (dcpromo)
- Database/SYSVOL path configuration
- Automatic reboot

### 3. Post-Reboot Services
- Wait for WinRM reconnection
- Monitor AD service startup (NTDS, DNS, Netlogon, W32Time, KDC)
- Service health verification

### 4. Health Validation (7 comprehensive tests)
- SYSVOL/NETLOGON share verification
- Replication status (repadmin /showrepl)
- Replication queue check (must be empty)
- dcdiag /test:dcpromo
- dcdiag /test:registerindns
- Full dcdiag suite
- dcdiag /test:dns

### 5. DNS Configuration (4 zones)
- Cross-domain forwarders (BIZ ↔ China)
- Microsoft GTM forwarder
- Microsoft STS forwarder
- DNS resolution verification

### 6. Authentication Validation
- Security event log monitoring
- Event IDs: 4624 (Logon), 4768 (Kerberos TGT), 4771 (Pre-auth)
- Authentication traffic verification

### 7. Security Agent Installation
- .NET Framework 4.8
- Azure AD Password Protection DC Agent
- Azure ATP Sensor
- Quest Change Auditor Agent
- Qualys version verification (≥6.2.5.4)

### 8. Final Configuration
- LDAPS auto-enrollment group membership
- Certificate enrollment trigger (certutil -pulse)
- Comprehensive deployment report
- Manual follow-up checklist

## Documentation

| Document | Description |
|----------|-------------|
| **[LAB-SETUP.md](docs/LAB-SETUP.md)** | **🧪 Start here: Lab environment setup and testing** |
| [AZURE-SETUP.md](docs/AZURE-SETUP.md) | Azure Key Vault and OIDC configuration |
| [GITHUB-ACTIONS-SETUP.md](docs/GITHUB-ACTIONS-SETUP.md) | Self-hosted runner and environment setup |

## Security

### Secrets Management
- All credentials stored in Azure Key Vault
- OIDC authentication (no static secrets in GitHub)
- Managed Identity for Key Vault access
- Automatic secret rotation support

### Access Control
- GitHub Environment protection rules
- Required reviewers for production
- Change ticket validation
- Complete audit trail

### Network Security
- Self-hosted runner in Azure VNet
- Private connectivity to DCs
- No public endpoint exposure
- NSG rules for least-privilege access

## Monitoring & Troubleshooting

### View Workflow Runs
```bash
# List recent runs
gh run list --workflow=deploy-prod.yml

# View specific run
gh run view RUN_ID

# Download logs
gh run download RUN_ID
```

### Check Deployment Reports
Reports are saved to `C:\Temp\DC-Deployment-Report-*.txt` on target DC and uploaded as GitHub Actions artifacts.

### Common Issues

**Issue: Workflow fails with "Access denied to Key Vault"**
- Check OIDC federated credentials are configured
- Verify app has "Key Vault Secrets User" role
- Ensure GitHub secrets are set correctly

**Issue: Cannot connect to Domain Controller**
- Verify self-hosted runner has network access
- Check DC is reachable on port 389 (LDAP)
- Ensure WinRM is enabled

**Issue: Health checks fail**
- Review DC deployment report
- Check AD replication status: `repadmin /showrepl`
- Run dcdiag manually: `dcdiag /v`

## Performance

Average execution time: **38 minutes**

| Phase | Duration |
|-------|----------|
| Pre-checks | 2 min |
| DC Promotion | 20 min |
| Health Validation | 8 min |
| Post-Configuration | 8 min |

## Support

| Contact | Purpose | Response Time |
|---------|---------|---------------|
| ad-ops@linkedin.com | Pipeline issues | 1 hour |
| GitHub Issues | Bug reports, features | 1 business day |
| Docs | Self-service | Immediate |

## Contributing

1. Create feature branch
2. Make changes
3. Run validation: `gh workflow run validate.yml`
4. Create PR (auto-validates)
5. Get approval
6. Merge

## License

Internal use only - LinkedIn Infrastructure

## Version History

- **2.0.0** (2026-01-17): Production release with GitHub Actions automation
- **1.0.0** (2026-01-14): Initial implementation

---

**Status**: ✅ Production Ready  
**Platform**: Azure + GitHub Actions  
**Runtime**: PowerShell 5.1+
