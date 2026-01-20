# Testing Without OIDC - Quick POC Approach

Since you don't have Azure AD permissions to create App Registrations, here's an alternative approach for **testing/POC only**.

## Problem

- ❌ Can't create Azure AD App Registration (requires admin permissions)
- ✅ DC01 has public IP (4.234.159.63)
- ✅ Can use GitHub-hosted runners (with security considerations)

## Solution: Direct PowerShell Execution (Testing Only)

### Option 1: Run PowerShell Directly (No GitHub Actions - Fastest for POC)

Test the pipeline locally from your machine:

```powershell
# 1. Test connectivity to DC01
Test-NetConnection 4.234.159.63 -Port 5985

# 2. Navigate to scripts
cd "v2-github-actions/scripts"

# 3. Run the pipeline directly (local secrets - POC only!)
$env:DOMAIN_ADMIN_USER = "linkedin\vamdev"
$env:DOMAIN_ADMIN_PASS = "Sarita123@@@"
$env:SAFE_MODE_PASS = "Sarita123@@@"

# 4. Execute pipeline
.\Invoke-DCPromotionPipeline.ps1 `
  -Environment lab `
  -TargetDC "4.234.159.63" `
  -UseLocalSecrets `
  -Verbose
```

**This bypasses:**
- GitHub Actions
- Azure Key Vault
- OIDC authentication

**Perfect for POC testing!**

---

### Option 2: Modified Workflow for GitHub Actions (With Basic Auth)

If you want to use GitHub Actions without OIDC:

#### Step 1: Store credentials as GitHub secrets (Less secure but works)

Go to GitHub → Settings → Secrets → Actions:

```
DOMAIN_ADMIN_USERNAME = linkedin\vamdev
DOMAIN_ADMIN_PASSWORD = Sarita123@@@
SAFE_MODE_PASSWORD = Sarita123@@@
```

#### Step 2: Create simplified workflow

Create `.github/workflows/deploy-lab-simple.yml`:

```yaml
name: Deploy to Lab (Simple - No OIDC)

on:
  workflow_dispatch:
    inputs:
      target_dc:
        description: 'Target DC IP or hostname'
        required: true
        type: string
        default: '4.234.159.63'

jobs:
  deploy:
    runs-on: ubuntu-latest  # GitHub-hosted runner
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Run DC Promotion Pipeline
        shell: pwsh
        run: |
          Write-Host "🧪 Running DC Promotion (Simple Mode)" -ForegroundColor Cyan
          
          cd v2-github-actions/scripts
          
          # Set credentials from secrets
          $env:DOMAIN_ADMIN_USER = "${{ secrets.DOMAIN_ADMIN_USERNAME }}"
          $env:DOMAIN_ADMIN_PASS = "${{ secrets.DOMAIN_ADMIN_PASSWORD }}"
          $env:SAFE_MODE_PASS = "${{ secrets.SAFE_MODE_PASSWORD }}"
          
          # Run pipeline with local secrets
          .\Invoke-DCPromotionPipeline.ps1 `
            -Environment lab `
            -TargetDC "${{ inputs.target_dc }}" `
            -UseLocalSecrets `
            -Verbose
```

---

### Option 3: Ask Azure Admin to Create App Registration

If you want the proper OIDC setup, ask your Azure AD admin to create:

**What to ask for:**

> "I need an Azure AD App Registration for GitHub Actions OIDC authentication with these settings:
> 
> - Display Name: `github-actions-dc-pipeline`
> - Federated Credential:
>   - Issuer: `https://token.actions.githubusercontent.com`
>   - Subject: `repo:YOUR_GITHUB_ORG/YOUR_REPO:environment:lab`
>   - Audiences: `api://AzureADTokenExchange`
> - Key Vault Access: Grant the Service Principal `get` and `list` permissions on `kv-dclab-0119`
> 
> Please provide me with the Application (Client) ID."

---

## Security Considerations for POC

### Current Setup
- DC01 public IP: 4.234.159.63
- WinRM port 5985 (HTTP) or 5986 (HTTPS)

### For Testing/POC

**Allow WinRM from GitHub Actions runners:**

```bash
# Get GitHub Actions IP ranges
curl https://api.github.com/meta | jq -r '.actions[]' > github-ips.txt

# Add NSG rule (example - adjust to your NSG name)
az network nsg rule create \
  --resource-group VAMDEVTEST \
  --nsg-name DC01-nsg \
  --name AllowWinRMFromGitHub \
  --priority 1000 \
  --source-address-prefixes $(cat github-ips.txt) \
  --destination-port-ranges 5985 \
  --access Allow \
  --protocol Tcp
```

**⚠️ WARNING:** This exposes WinRM to the internet. Only do this for temporary POC testing!

---

## Recommended POC Flow

### Quick Test (5 minutes)

```powershell
# From your local machine
cd "LinkedIn - DC IaaC Build/v2-github-actions/scripts"

# Test just pre-checks
Import-Module .\modules\PrePromotionChecks.psm1
Invoke-AllPreChecks -TargetDC "4.234.159.63" -Credential (Get-Credential)
```

### Full Test (40 minutes)

```powershell
# Set environment variables
$env:DOMAIN_ADMIN_USER = "linkedin\vamdev"
$env:DOMAIN_ADMIN_PASS = "Sarita123@@@"
$env:SAFE_MODE_PASS = "Sarita123@@@"

# Run full pipeline
.\Invoke-DCPromotionPipeline.ps1 `
  -Environment lab `
  -TargetDC "4.234.159.63" `
  -UseLocalSecrets `
  -Verbose
```

---

## What You Need Next

### For Option 1 (Local PowerShell - Recommended for POC):
1. ✅ DC01 running (already done)
2. ✅ Credentials (already have)
3. ✅ Network access to 4.234.159.63:5985
4. → Run PowerShell script from your machine

### For Option 2 (GitHub Actions Simple):
1. ✅ DC01 running
2. → Add 3 GitHub secrets (credentials)
3. → Open NSG for WinRM from GitHub IPs
4. → Create simplified workflow
5. → Run workflow

### For Option 3 (Proper OIDC - Production Ready):
1. → Get Azure AD admin to create App Registration
2. → Get AZURE_CLIENT_ID from admin
3. → Follow original GITHUB-SETUP-GUIDE.md

---

## Next Steps

**For immediate POC testing, I recommend Option 1:**

1. Open PowerShell on your machine
2. Test connectivity: `Test-NetConnection 4.234.159.63 -Port 5985`
3. Run the pipeline directly
4. Validate it works

**Once validated, you can:**
- Get proper Azure AD permissions
- Set up OIDC properly
- Use GitHub Actions with full security

---

**Want me to help you test Option 1 right now?**
