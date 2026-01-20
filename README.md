# LinkedIn DC Infrastructure as Code - Automated DC Build

Automated Domain Controller provisioning for the linkedin.local domain using GitHub Actions and Azure.

## 🚀 Quick Start

### One-Command DC Deployment

Create a new Domain Controller from scratch in ~7 minutes:

```bash
# Trigger via GitHub CLI
gh workflow run full-dc-automation.yml \
  --repo vamdevz/autodcbuild \
  -f vm_name="DC03" \
  -f admin_username="azureuser"
```

Or use the GitHub UI:
1. Go to **Actions** tab
2. Select **Full DC Automation**
3. Click **Run workflow**
4. Enter VM name (e.g., `DC03`)
5. Click **Run workflow**

**That's it!** In ~7 minutes you'll have a fully functional DC in the linkedin.local domain.

---

## 📋 Workflows

### 1. Full DC Automation (Recommended)
**File**: `.github/workflows/full-dc-automation.yml`  
**Purpose**: Complete end-to-end automation - creates VM and promotes to DC

**Steps**:
1. Creates Windows Server 2019 VM in Azure
2. Configures networking (NSG, Public IP, NIC)
3. Enables WinRM for remote management
4. Installs AD DS Role
5. Configures DNS to point to DC01
6. Promotes to Domain Controller
7. Verifies successful promotion

**Duration**: ~7 minutes  
**Use Case**: Creating new DCs from scratch

**Inputs**:
- `vm_name` (required): Name for the new VM (e.g., "DC03")
- `admin_username` (optional): Local admin username (default: "azureuser")
- `skip_validation` (optional): Skip pre-checks (default: false)

### 2. Create VM Only
**File**: `.github/workflows/create-vm.yml`  
**Purpose**: Create and configure a Windows Server VM (no DC promotion)

**Duration**: ~2-3 minutes  
**Use Case**: Creating standalone Windows servers or testing VM creation

**Outputs**:
- `vm_name`: Name of created VM
- `vm_ip`: Public IP address

### 3. Promote Existing VM to DC
**File**: `.github/workflows/deploy-lab.yml`  
**Purpose**: Promote an existing Windows Server to Domain Controller

**Duration**: ~4-5 minutes  
**Use Case**: Promoting a pre-existing or manually created VM

**Inputs**:
- `vm_name` (required): Name of existing VM
- `target_dc` (optional): IP address reference
- `admin_username` (optional): Local admin username
- `skip_validation` (optional): Skip pre-checks

---

## ⚙️ Setup

### Prerequisites

1. **Azure Resources**:
   - Resource Group: `VAMDEVTEST`
   - VNet: `DC01-vnet` in `uksouth` region
   - Existing DC: `DC01` (Primary DC for linkedin.local)

2. **GitHub Secrets** (already configured):
   ```
   AZURE_CREDENTIALS         # Azure Service Principal JSON
   AZURE_CLIENT_ID           # Service Principal Client ID  
   AZURE_CLIENT_SECRET       # Service Principal Secret
   AZURE_TENANT_ID           # Azure Tenant ID
   AZURE_SUBSCRIPTION_ID     # Azure Subscription ID
   DOMAIN_ADMIN_USERNAME     # linkedin.local\vamdev
   DOMAIN_ADMIN_PASSWORD     # Domain admin password
   SAFE_MODE_PASSWORD        # DSRM password
   ```

### First Time Setup (Already Done)

<details>
<summary>Click to expand setup steps (for reference only)</summary>

1. **Create Azure Service Principal**:
   ```bash
   az login --use-device-code
   az ad sp create-for-rbac --name "GitHubActions-DC-Automation" --role Contributor --scopes /subscriptions/{subscription-id}/resourceGroups/VAMDEVTEST
   ```

2. **Add GitHub Secrets**:
   ```bash
   gh secret set AZURE_CREDENTIALS < credentials.json
   gh secret set DOMAIN_ADMIN_USERNAME -b "linkedin.local\vamdev"
   gh secret set DOMAIN_ADMIN_PASSWORD -b "YourPassword"
   gh secret set SAFE_MODE_PASSWORD -b "YourPassword"
   ```

3. **Verify Network**:
   ```bash
   az network vnet show --resource-group VAMDEVTEST --name DC01-vnet
   ```

</details>

---

## 🎯 Usage Examples

### Example 1: Create a New DC

```bash
gh workflow run full-dc-automation.yml \
  --repo vamdevz/autodcbuild \
  -f vm_name="DC04" \
  -f admin_username="azureuser"
```

**Expected Output**:
- VM Created: ~2-3 minutes
- DC Promotion: ~4-5 minutes
- **Total**: ~7 minutes
- New DC: `DC04.linkedin.local`

### Example 2: Create Multiple DCs

```bash
# Create DC05
gh workflow run full-dc-automation.yml --repo vamdevz/autodcbuild -f vm_name="DC05"

# Wait 7 minutes, then create DC06
gh workflow run full-dc-automation.yml --repo vamdevz/autodcbuild -f vm_name="DC06"
```

### Example 3: Create VM Only (No Promotion)

```bash
gh workflow run create-vm.yml \
  --repo vamdevz/autodcbuild \
  -f vm_name="AppServer01"
```

### Example 4: Promote Existing VM

```bash
gh workflow run deploy-lab.yml \
  --repo vamdevz/autodcbuild \
  -f vm_name="ExistingVM01" \
  -f admin_username="azureuser"
```

---

## 🔍 Monitoring

### View Running Workflows

```bash
# List recent runs
gh run list --repo vamdevz/autodcbuild

# Watch a specific run
gh run watch <run-id> --repo vamdevz/autodcbuild

# View logs
gh run view <run-id> --repo vamdevz/autodcbuild --log
```

### Check DC Status

```bash
# Via Azure CLI
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts "Get-Service NTDS,DNS,Netlogon,KDC | Format-Table"
```

### RDP Access

```bash
# Get VM IP
az vm show --resource-group VAMDEVTEST --name DC03 --show-details --query publicIps -o tsv

# RDP with local admin
mstsc /v:<public-ip>
Username: azureuser
Password: (from DOMAIN_ADMIN_PASSWORD secret)

# RDP with domain admin (after promotion)
mstsc /v:<public-ip>
Username: linkedin.local\vamdev
Password: (from DOMAIN_ADMIN_PASSWORD secret)
```

---

## 🛠️ Troubleshooting

### Workflow Failed at VM Creation

**Symptoms**: Workflow fails in "Create VM" step

**Common Causes**:
1. **Region Mismatch**: Ensure resources are in `uksouth`
2. **Quota Exceeded**: Check Azure VM quota
3. **Network Issues**: Verify VNet `DC01-vnet` exists

**Solution**:
```bash
# Check resource group region
az group show --name VAMDEVTEST --query location

# Check VNet
az network vnet show --resource-group VAMDEVTEST --name DC01-vnet

# Check quota
az vm list-usage --location uksouth --query "[?name.value=='standardDFamily']"
```

### Workflow Failed at DC Promotion

**Symptoms**: VM created but DC promotion fails

**Common Causes**:
1. **DNS Not Configured**: VM can't reach DC01
2. **Domain Credentials Invalid**: Check secrets
3. **AD DS Role Not Installed**: Check previous step

**Solution**:
```bash
# Test DNS from VM
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts "Resolve-DnsName DC01.linkedin.local"

# Test domain connectivity
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts "Test-NetConnection -ComputerName 10.0.0.6 -Port 389"
```

### DC Promotion Succeeded But Workflow Reports Failure

**Cause**: Emoji encoding issues in Azure VM run-command output

**Verification**:
```bash
# Check if DC services are running
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts "Get-Service NTDS -ErrorAction SilentlyContinue | Select-Object Status"
```

**Status**: This issue is fixed in the latest version (checks for "Operation completed successfully" text instead of emojis)

### Workflow Stuck/Slow

**Expected Durations**:
- VM Creation: 2-3 minutes
- DC Promotion: 4-5 minutes
- Total: 7-10 minutes

**If slower than 15 minutes**:
1. Check Azure status: https://status.azure.com
2. Check GitHub Actions status: https://www.githubstatus.com
3. Review workflow logs for specific delays

---

## 📁 Repository Structure

```
autodcbuild/
├── .github/workflows/
│   ├── full-dc-automation.yml    # Main: End-to-end automation
│   ├── create-vm.yml              # Step 1: VM creation
│   └── deploy-lab.yml             # Step 2: DC promotion
│
├── v2-github-actions/
│   └── scripts/
│       ├── setup-winrm.ps1        # WinRM configuration
│       └── modules/               # PowerShell modules (legacy)
│
├── docs/                          # Additional documentation
└── README.md                      # This file
```

---

## 🔐 Security Considerations

### Credentials
- All passwords stored as GitHub Secrets (encrypted)
- Secrets never logged or displayed in workflow output
- Azure Service Principal has minimal required permissions (Contributor on VAMDEVTEST RG only)

### Network Security
- NSG rules created per-VM (RDP and WinRM from Internet - **lab only!**)
- Production: Restrict source IPs and use Azure Bastion
- VMs on private VNet with DC01

### Best Practices
- ✅ Use Azure Key Vault for secrets (optional enhancement)
- ✅ Enable Azure AD authentication
- ✅ Use JIT (Just-In-Time) access for RDP
- ⚠️ Current setup is for **LAB ENVIRONMENT ONLY**

---

## 🚦 Workflow Status

| Workflow | Status | Duration | Last Tested |
|----------|--------|----------|-------------|
| Full DC Automation | ✅ Working | ~7 min | 2026-01-20 |
| Create VM | ✅ Working | ~2-3 min | 2026-01-20 |
| DC Promotion | ✅ Working | ~4-5 min | 2026-01-20 |

**Last Successful Full Test**:
- Run ID: 21180681943
- VM: AutoDC2244
- Result: ✅ Success (7 minutes)
- Verification: All AD services running

---

## 📚 Additional Resources

- [Azure VM Documentation](https://docs.microsoft.com/azure/virtual-machines/)
- [Active Directory PowerShell Module](https://docs.microsoft.com/powershell/module/activedirectory/)
- [GitHub Actions Documentation](https://docs.github.com/actions)
- [Install-ADDSDomainController](https://docs.microsoft.com/powershell/module/addsdeployment/install-addsdomaincontroller)

---

## 🤝 Contributing

1. Create a feature branch
2. Make changes
3. Test thoroughly (create test VM)
4. Submit pull request
5. Cleanup test resources

---

## 📝 License

Internal use only - LinkedIn Infrastructure

---

## 📞 Support

For issues or questions:
1. Check **Troubleshooting** section above
2. Review workflow logs in GitHub Actions
3. Contact: Infrastructure Team

---

**Happy DC Building! 🎉**
