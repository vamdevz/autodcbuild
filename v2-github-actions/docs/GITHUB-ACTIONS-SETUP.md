# GitHub Actions Setup Guide

Guide for configuring self-hosted runners and GitHub environments.

## Self-Hosted Runner Deployment

### Option 1: Azure VM Runner

**Create Windows Server VM:**

```bash
az vm create \
  --resource-group rg-dc-automation \
  --name runner-dc-promotion \
  --image Win2022Datacenter \
  --size Standard_B2s \
  --admin-username adminuser \
  --admin-password 'SecurePassword123!' \
  --vnet-name vnet-dc-automation \
  --subnet subnet-runners
```

**Configure Runner on VM:**

1. RDP to the VM
2. Download GitHub Actions runner:
   ```powershell
   mkdir C:\actions-runner
   cd C:\actions-runner
   Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-win-x64-2.311.0.zip -OutFile actions-runner.zip
   Expand-Archive -Path actions-runner.zip -DestinationPath .
   ```

3. Configure runner:
   ```powershell
   .\config.cmd --url https://github.com/YOUR_ORG/YOUR_REPO --token YOUR_RUNNER_TOKEN
   ```

4. Install as service:
   ```powershell
   .\svc.cmd install
   .\svc.cmd start
   ```

### Option 2: Azure Container Instances (ACI)

Coming soon - ephemeral runners using ACI.

## GitHub Environments Setup

### Create Staging Environment

1. Go to repository Settings → Environments
2. Click "New environment"
3. Name: `staging`
4. Configure protection rules:
   - No required reviewers (auto-deploy)
   - Deployment branches: Select branches only

### Create Production Environment

1. Click "New environment"
2. Name: `production`
3. Configure protection rules:
   - ✅ Required reviewers: Add reviewers
   - ✅ Wait timer: 5 minutes (optional)
   - Deployment branches: Select branches only (main/master)

## Runner Network Configuration

Ensure runner can access:
- Domain Controllers (LDAP port 389, WinRM 5985/5986)
- Azure Key Vault (HTTPS 443)
- GitHub APIs (HTTPS 443)

**NSG Rules:**

```bash
# Allow outbound to DCs
az network nsg rule create \
  --resource-group rg-dc-automation \
  --nsg-name nsg-runners \
  --name AllowDCAccess \
  --priority 100 \
  --direction Outbound \
  --destination-address-prefixes 10.0.0.0/8 \
  --destination-port-ranges 389 5985 5986 \
  --protocol Tcp
```

## Runner Maintenance

### Update Runner

```powershell
cd C:\actions-runner
.\svc.cmd stop
# Download new version
.\config.cmd remove --token YOUR_TOKEN
.\config.cmd --url https://github.com/YOUR_ORG/YOUR_REPO --token YOUR_NEW_TOKEN
.\svc.cmd install
.\svc.cmd start
```

### Monitor Runner Health

```powershell
# Check service status
Get-Service actions.runner.*

# View logs
Get-Content C:\actions-runner\_diag\Runner_*.log -Tail 50
```

## Workflow Triggers

### Manual Deployment (Recommended)

```yaml
on:
  workflow_dispatch:
    inputs:
      target_dc:
        required: true
```

Trigger via:
- GitHub UI: Actions → Select workflow → Run workflow
- GitHub CLI: `gh workflow run deploy-staging.yml -f target_dc=stg-dc01`

### PR-Based Validation

```yaml
on:
  pull_request:
    branches: [main, master]
```

Automatically runs on PR creation/update.

## Testing the Setup

1. **Test Validation Workflow:**
   ```bash
   # Create test PR
   git checkout -b test-workflow
   git commit --allow-empty -m "test: validate workflow"
   git push origin test-workflow
   gh pr create --title "Test Workflow" --body "Testing validation"
   ```

2. **Test Staging Deployment:**
   ```bash
   gh workflow run deploy-staging.yml \
     -f target_dc=stg-dc01.staging.linkedin.biz
   ```

3. **Test Production (with approval):**
   ```bash
   gh workflow run deploy-prod.yml \
     -f target_dc=lva1-dc03.linkedin.biz \
     -f change_ticket=CHG0012345
   ```

## Troubleshooting

### Runner Won't Connect

- Check network connectivity to GitHub
- Verify runner token is valid
- Review runner logs: `C:\actions-runner\_diag\`

### Workflow Fails with Permission Error

- Check Azure OIDC authentication
- Verify GitHub secrets are set
- Ensure Key Vault access granted

### Can't Access Domain Controllers

- Verify NSG rules allow traffic
- Check WinRM is enabled on runner
- Test connectivity: `Test-NetConnection -ComputerName DC01 -Port 389`

## Next Steps

- [Azure Setup Guide](AZURE-SETUP.md)
- Return to [Main README](../README.md)
