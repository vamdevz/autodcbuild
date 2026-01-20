# Lab Environment - Quick Start

**Status**: ✅ Ready for Testing  
**Last Updated**: 2026-01-19

## Current Setup

### ✅ Completed
- [x] DC01 VM running (4.234.159.63)
- [x] Azure Key Vault configured (kv-dclab-0119)
- [x] Domain credentials stored
- [x] Lab configuration files created

### 🔄 Next Steps
1. Configure GitHub secrets
2. Deploy self-hosted runner
3. Run first test deployment

---

## Lab Infrastructure

| Component | Value | Status |
|-----------|-------|--------|
| **VM** | DC01 | ✅ Running |
| **Public IP** | 4.234.159.63 | |
| **Private IP** | 10.0.0.6 | |
| **Domain** | linkedin.local | |
| **Resource Group** | VAMDEVTEST | |
| **Key Vault** | kv-dclab-0119 | ✅ Configured |

---

## Quick Commands

### Start DC01
```bash
az vm start --resource-group VAMDEVTEST --name DC01
# Or use: ./start-dc01.sh
```

### Stop DC01 (to save costs)
```bash
az vm deallocate --resource-group VAMDEVTEST --name DC01
```

### Check DC01 Status
```bash
az vm show --resource-group VAMDEVTEST --name DC01 --show-details \
  --query "{Name:name, PowerState:powerState, PublicIP:publicIps}" -o table
```

### Test Connectivity
```powershell
# Test WinRM (port 5985)
Test-NetConnection 4.234.159.63 -Port 5985

# Test LDAP (port 389) - if DC already promoted
Test-NetConnection 4.234.159.63 -Port 389
```

### Access Key Vault Secrets
```bash
# List secrets
az keyvault secret list --vault-name kv-dclab-0119 --query "[].name" -o tsv

# Get a secret
az keyvault secret show --vault-name kv-dclab-0119 --name DomainAdminUsername --query "value" -o tsv
```

---

## GitHub Configuration

### Required Repository Secrets

Go to: GitHub Repository → Settings → Secrets and variables → Actions

Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `KEY_VAULT_NAME` | `kv-dclab-0119` |
| `AZURE_TENANT_ID` | `0d9e3fa8-707c-4e1a-8885-aa65b35ad4b5` |
| `AZURE_SUBSCRIPTION_ID` | `81adc0ae-0abb-443d-9b8b-05cb650a2d46` |
| `AZURE_CLIENT_ID` | *(from Azure AD App Registration)* |

### Create GitHub Environment

1. Go to: Settings → Environments → New environment
2. Name: `lab`
3. Protection rules: None (for easy testing)
4. Click "Configure environment"

---

## Self-Hosted Runner Setup

### Option 1: Windows VM Runner (Recommended)

Deploy a Windows VM in the same VNet as DC01:

```bash
# Create Windows VM for runner
az vm create \
  --resource-group VAMDEVTEST \
  --name runner-vm \
  --image Win2022Datacenter \
  --size Standard_D2s_v3 \
  --admin-username azureuser \
  --vnet-name DC01-vnet \
  --subnet default
```

Then follow GitHub's runner setup instructions:
- Settings → Actions → Runners → New self-hosted runner → Windows

### Option 2: Use Existing Windows Machine

If you have a Windows machine with network access to DC01:
1. Download GitHub Actions runner
2. Configure it with your repository
3. Install as Windows service
4. Ensure connectivity to DC01

**Test connectivity from runner:**
```powershell
Test-NetConnection dc01.linkedin.local -Port 5985
Test-NetConnection 4.234.159.63 -Port 5985
```

---

## Run Your First Lab Deployment

### Via GitHub UI

1. Go to: **Actions** tab
2. Select: **"Deploy to Lab"** workflow
3. Click: **"Run workflow"**
4. Enter:
   - **target_dc**: `dc01.linkedin.local`
   - **skip_validation**: ☐ (leave unchecked)
5. Click: **"Run workflow"**
6. Monitor execution

### Via GitHub CLI

```bash
# Deploy to lab
gh workflow run deploy-lab.yml \
  -f target_dc=dc01.linkedin.local \
  -f skip_validation=false

# Watch the run
gh run watch

# View logs
gh run view --log
```

### Expected Duration
- Pre-checks: ~2 minutes
- DC Promotion: ~15 minutes
- Health Checks: ~8 minutes
- Post-Config: ~5 minutes
- **Total: ~30-40 minutes**

---

## Troubleshooting

### DC01 Not Accessible
```bash
# Check VM is running
az vm show --resource-group VAMDEVTEST --name DC01 --query "powerState"

# If stopped, start it
az vm start --resource-group VAMDEVTEST --name DC01
```

### Key Vault Access Denied
```bash
# Check current user has access
az keyvault show --name kv-dclab-0119 --query "properties.accessPolicies"

# Grant yourself access
az keyvault set-policy \
  --name kv-dclab-0119 \
  --upn YOUR_EMAIL@domain.com \
  --secret-permissions get list
```

### Runner Can't Connect to DC01
```powershell
# From runner, test network
Test-NetConnection 4.234.159.63 -Port 5985
Test-NetConnection 10.0.0.6 -Port 5985

# Check NSG rules
az network nsg rule list --resource-group VAMDEVTEST --nsg-name DC01-nsg
```

---

## Cost Management

### Minimize Costs

Stop DC01 when not testing:
```bash
# Stop (deallocate) DC01
az vm deallocate --resource-group VAMDEVTEST --name DC01

# Start when needed
az vm start --resource-group VAMDEVTEST --name DC01
```

**Estimated Costs** (when running):
- DC01 VM: ~$0.10-0.20/hour
- Storage: ~$5/month
- Key Vault: ~$0.03/10,000 operations

---

## Files Reference

| File | Purpose |
|------|---------|
| `config/lab.json` | Lab environment configuration |
| `lab-keyvault-info.txt` | Key Vault credentials reference |
| `.github/workflows/deploy-lab.yml` | Lab deployment workflow |
| `docs/LAB-SETUP.md` | Detailed setup guide |
| `start-dc01.sh` | Quick VM start script |

---

## What's Next?

1. **Immediate**: Set up GitHub secrets and runner
2. **Testing**: Run first deployment to validate
3. **Staging**: After lab success, configure staging environment
4. **Production**: Final deployment to production DCs

---

**Need Help?**  
See detailed guide: [docs/LAB-SETUP.md](docs/LAB-SETUP.md)

---

**Lab Status**: 🧪 Ready for Testing  
**DC01**: ✅ Running  
**Key Vault**: ✅ Configured  
**Next**: Configure GitHub & Deploy Runner
