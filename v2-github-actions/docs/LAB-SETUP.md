# Lab Environment Setup Guide

Complete guide for setting up and testing the DC promotion pipeline in an isolated Azure lab environment.

## Lab Environment Overview

| Component | Value |
|-----------|-------|
| **Environment** | lab (isolated) |
| **Domain** | linkedin.local |
| **Primary DC** | dc01.linkedin.local |
| **Purpose** | Testing and validation before staging/production |
| **Network** | Isolated Azure VNet |

## Prerequisites

### 1. Azure Resources

- ✅ Azure subscription
- ✅ Isolated VNet for lab environment
- ✅ Windows Server 2019/2022 VM (dc01)
- ✅ Azure Key Vault (can be shared or dedicated)
- ✅ Self-hosted GitHub Actions runner

### 2. Lab Domain Controller (dc01)

**Minimum Requirements:**
- Windows Server 2019 or 2022
- 4 GB RAM minimum (8 GB recommended)
- 60 GB disk space
- Network connectivity to GitHub runner
- WinRM enabled

**Pre-configured:**
```powershell
# On dc01.linkedin.local

# 1. Enable WinRM
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force

# 2. Create required drives (if not exists)
# D: drive for AD database
# If only C: exists, the pipeline will use C:\Windows\NTDS

# 3. Install PowerShell modules
Install-Module -Name ActiveDirectory -Force

# 4. Set hostname
Rename-Computer -NewName "dc01" -Restart
```

### 3. GitHub Configuration

**Required Secrets** (Settings → Secrets → Actions):
```
AZURE_CLIENT_ID         # Azure AD App Registration client ID
AZURE_TENANT_ID         # Azure tenant ID
AZURE_SUBSCRIPTION_ID   # Azure subscription ID
KEY_VAULT_NAME          # Azure Key Vault name (e.g., kv-dcpromotion-lab)
```

**Required Environment** (Settings → Environments):
- Name: `lab`
- Protection rules: None (for easy testing)
- Secrets: None (uses repository secrets)

## Step 1: Azure Key Vault Setup

### 1.1 Create Lab Key Vault

```bash
# Create resource group
az group create --name rg-dcpromotion-lab --location eastus

# Create Key Vault
az keyvault create \
  --name kv-dcpromotion-lab \
  --resource-group rg-dcpromotion-lab \
  --location eastus

# Note: Save the Key Vault name for GitHub secrets
```

### 1.2 Store Lab Credentials

```bash
# Domain admin credentials (create these in your lab domain first)
az keyvault secret set \
  --vault-name kv-dcpromotion-lab \
  --name DomainAdminUsername \
  --value "LINKEDIN\Administrator"

az keyvault secret set \
  --vault-name kv-dcpromotion-lab \
  --name DomainAdminPassword \
  --value "YourSecurePassword123!"

# Safe mode password (for DC recovery)
az keyvault secret set \
  --vault-name kv-dcpromotion-lab \
  --name SafeModePassword \
  --value "YourSafeModePassword123!"
```

### 1.3 Grant Access to GitHub Actions

See [AZURE-SETUP.md](AZURE-SETUP.md) for detailed OIDC configuration.

Quick version:
```bash
# Create federated credential for lab environment
az ad app federated-credential create \
  --id <APP_ID> \
  --parameters '{
    "name": "GitHubActionsLab",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<ORG>/<REPO>:environment:lab",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Grant Key Vault access
az keyvault set-policy \
  --name kv-dcpromotion-lab \
  --object-id <APP_OBJECT_ID> \
  --secret-permissions get list
```

## Step 2: Self-Hosted Runner Setup

### 2.1 Deploy Runner in Azure

**Option A: Windows VM Runner (Recommended for lab)**

```powershell
# On a Windows VM in the same VNet as dc01

# 1. Download runner
cd C:\actions-runner
# Follow GitHub instructions: Settings → Actions → Runners → New runner

# 2. Configure runner
.\config.cmd --url https://github.com/<ORG>/<REPO> --token <TOKEN>

# 3. Install as service
.\svc.sh install
.\svc.sh start

# 4. Verify connectivity to dc01
Test-NetConnection dc01.linkedin.local -Port 5985  # WinRM
Test-NetConnection dc01.linkedin.local -Port 389   # LDAP
```

### 2.2 Configure Runner Labels

In GitHub, add labels to runner:
- `self-hosted`
- `lab` (optional, for targeting)

## Step 3: Lab Configuration Review

### 3.1 Review Lab Config

Check `config/lab.json`:
```json
{
  "environment": "lab",
  "domain_name": "linkedin.local",
  "target_host": "dc01.linkedin.local",
  "skip_agents": true,              // No enterprise agents in lab
  "skip_ldaps_group": true,         // No LDAPS auto-enrollment in lab
  "lab_mode": true                  // Relaxed validation
}
```

### 3.2 Customize for Your Lab

Edit `config/lab.json` if needed:
```bash
cd v2-github-actions/config
# Update IP addresses, hostnames, or skip options
```

## Step 4: Run Your First Lab Deployment

### 4.1 Via GitHub UI (Easiest)

1. Go to GitHub repository → **Actions** tab
2. Select workflow: **"Deploy to Lab"**
3. Click **"Run workflow"**
4. Enter inputs:
   - **Target DC**: `dc01.linkedin.local`
   - **Skip validation**: `false` (uncheck for first run)
5. Click **"Run workflow"**
6. Monitor execution in real-time

### 4.2 Via GitHub CLI

```bash
# Deploy to lab
gh workflow run deploy-lab.yml \
  -f target_dc=dc01.linkedin.local \
  -f skip_validation=false

# Monitor the run
gh run watch

# View logs
gh run view --log
```

### 4.3 Expected Output

The pipeline will:
1. ✅ Run pre-promotion checks (~2 min)
2. ✅ Install AD DS role (~5 min)
3. ✅ Promote DC (~15 min)
4. ✅ Reboot and wait for services (~5 min)
5. ✅ Run health checks (~8 min)
6. ✅ Configure DNS (minimal in lab) (~2 min)
7. ✅ Generate report (~1 min)

**Total time: ~40 minutes**

## Step 5: Validate Lab Deployment

### 5.1 Check GitHub Actions Output

Review the workflow run logs for any errors or warnings.

### 5.2 Download Deployment Report

```bash
# Download artifacts
gh run download <RUN_ID>

# Or from UI: Actions → Run → Artifacts → Download
```

### 5.3 Verify on DC01

```powershell
# RDP or connect to dc01.linkedin.local

# 1. Verify DC role
Get-ADDomainController -Identity dc01

# 2. Check services
Get-Service NTDS, DNS, Netlogon, W32Time, KDC

# 3. Check replication (if you have multiple DCs)
repadmin /showrepl

# 4. Run dcdiag
dcdiag /v

# 5. Check DNS
nslookup dc01.linkedin.local
nslookup linkedin.local

# 6. Review deployment report
Get-Content C:\Temp\DC-Deployment-Report-*.txt
```

## Step 6: Testing Iterations

### 6.1 Quick Re-test (Skip Checks)

For rapid iteration during testing:
```bash
gh workflow run deploy-lab.yml \
  -f target_dc=dc01.linkedin.local \
  -f skip_validation=true
```

### 6.2 Test Individual Modules

```powershell
# On the runner or dc01, test modules directly

cd v2-github-actions/scripts/modules

# Import and test
Import-Module .\PrePromotionChecks.psm1
Invoke-AllPreChecks -TargetDC "dc01.linkedin.local"
```

### 6.3 Rollback/Reset Lab

If you need to start over:
```powershell
# On dc01, demote DC
Uninstall-ADDSDomainController -DemoteOperationMasterRole -RemoveApplicationPartition

# Or rebuild VM from snapshot
```

## Step 7: Troubleshooting

### Common Issues

#### Issue 1: Runner cannot connect to dc01
```powershell
# On runner, test connectivity
Test-NetConnection dc01.linkedin.local -Port 5985

# On dc01, verify WinRM
Get-Service WinRM
Test-WSMan -ComputerName localhost
```

**Fix:**
```powershell
# On dc01
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force
Restart-Service WinRM
```

#### Issue 2: Key Vault access denied
```bash
# Verify federated credential exists
az ad app federated-credential list --id <APP_ID>

# Verify Key Vault permissions
az keyvault show --name kv-dcpromotion-lab --query properties.accessPolicies
```

#### Issue 3: Pre-checks fail
Check specific failure:
- **Domain membership**: Ensure dc01 can resolve linkedin.local
- **Disk space**: Verify C: or D: has 20GB+ free
- **DC connectivity**: If no existing DCs, this check may fail (safe to skip in lab)

**Workaround:**
```bash
# Run with skip_validation=true for first DC in new domain
gh workflow run deploy-lab.yml \
  -f target_dc=dc01.linkedin.local \
  -f skip_validation=true
```

#### Issue 4: Pipeline hangs
- Check runner is online: GitHub → Settings → Actions → Runners
- Check runner logs: `C:\actions-runner\_diag\` on runner VM
- Verify no firewall blocking: NSG rules, Windows Firewall

### Enable Debug Logging

For detailed troubleshooting:
```bash
# Set GitHub Actions secret
# ACTIONS_STEP_DEBUG = true
# ACTIONS_RUNNER_DEBUG = true

# Re-run workflow to see verbose logs
```

## Step 8: Ready for Staging

Once lab testing is successful:

### 8.1 Validation Checklist

- [ ] Pipeline completes without errors
- [ ] All health checks pass (7/7)
- [ ] DC services running (NTDS, DNS, Netlogon, W32Time, KDC)
- [ ] dcdiag returns no critical errors
- [ ] Deployment report generated
- [ ] Runner and Key Vault integration working

### 8.2 Document Findings

Create a summary:
```markdown
## Lab Test Results

- **Date**: 2026-01-17
- **Target**: dc01.linkedin.local
- **Duration**: 38 minutes
- **Result**: ✅ Success
- **Issues**: None
- **Notes**: Ready for staging
```

### 8.3 Proceed to Staging

1. Review `config/staging.json`
2. Update staging environment in GitHub
3. Run `deploy-staging.yml` workflow
4. See [AZURE-SETUP.md](AZURE-SETUP.md) for staging setup

## Lab Environment Differences

| Feature | Lab | Staging | Production |
|---------|-----|---------|------------|
| **Domain** | linkedin.local | staging.linkedin.biz | linkedin.biz |
| **Approval** | None | Optional | Required |
| **Agents** | Skipped | Installed | Installed |
| **LDAPS Group** | Skipped | Added | Added |
| **DNS Forwarders** | None | 3 zones | 4 zones |
| **Change Ticket** | Not required | Optional | Required |
| **Validation** | Can skip | Recommended | Mandatory |

## Lab Configuration Reference

### Minimal lab.json
```json
{
  "environment": "lab",
  "domain_name": "linkedin.local",
  "target_host": "dc01.linkedin.local",
  "skip_agents": true,
  "skip_ldaps_group": true,
  "lab_mode": true
}
```

### Full lab.json (all options)
```json
{
  "environment": "lab",
  "domain_name": "linkedin.local",
  "primary_dc_ip": "10.0.0.4",
  "ad_site_name": "Lab-Site",
  "target_host": "dc01.linkedin.local",
  "required_drives": ["C", "D"],
  "min_disk_space_gb": 20,
  "dns_forwarders": {},
  "skip_agents": true,
  "skip_ldaps_group": true,
  "skip_certificate_enrollment": true,
  "lab_mode": true,
  "timeout_minutes": 60
}
```

## Support

- **Lab Issues**: Create GitHub issue with `lab` label
- **Azure Questions**: See [AZURE-SETUP.md](AZURE-SETUP.md)
- **Runner Issues**: See [GITHUB-ACTIONS-SETUP.md](GITHUB-ACTIONS-SETUP.md)

---

**Next Steps:**
1. ✅ Complete lab setup (this guide)
2. → Test in staging environment
3. → Deploy to production

**Status**: Ready for lab testing 🧪  
**Last Updated**: 2026-01-19
