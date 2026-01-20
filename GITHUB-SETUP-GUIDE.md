# GitHub Setup Guide - Quick & Simple

This guide helps you complete the GitHub configuration needed to run the DC promotion pipeline.

---

## Prerequisites

✅ Already completed:
- [x] DC01 VM running
- [x] Azure Key Vault configured
- [x] Lab configuration files created

🔄 What we'll do now:
- [ ] Create Azure AD App Registration (get AZURE_CLIENT_ID)
- [ ] Add GitHub secrets
- [ ] Set up runner (choose easiest option)

---

## Step 1: Get AZURE_CLIENT_ID (5 minutes)

### Automated Setup (Recommended)

Run the provided script:

```bash
cd "/Volumes/Vamdev Data/Downloads/Projects/LinkedIn - DC IaaC Build"
./setup-azure-app-registration.sh
```

The script will:
1. Create Azure AD App Registration
2. Configure OIDC for GitHub Actions
3. Grant Key Vault access
4. Display your AZURE_CLIENT_ID

**Save the output - you'll need it for GitHub secrets!**

### Manual Setup (if script doesn't work)

<details>
<summary>Click to expand manual instructions</summary>

#### 1. Create App Registration

```bash
# Create the app
az ad app create --display-name "github-actions-dc-pipeline"

# Get the Client ID (save this!)
az ad app list --display-name "github-actions-dc-pipeline" --query "[0].appId" -o tsv
```

#### 2. Create Service Principal

```bash
APP_ID="<paste-client-id-here>"
az ad sp create --id $APP_ID
```

#### 3. Get Service Principal Object ID

```bash
SP_OBJECT_ID=$(az ad sp show --id $APP_ID --query id -o tsv)
echo $SP_OBJECT_ID
```

#### 4. Grant Key Vault Access

```bash
az keyvault set-policy \
  --name kv-dclab-0119 \
  --object-id $SP_OBJECT_ID \
  --secret-permissions get list
```

#### 5. Create Federated Credential for OIDC

Replace `YOUR_ORG` and `YOUR_REPO`:

```bash
APP_OBJECT_ID=$(az ad app show --id $APP_ID --query id -o tsv)

az ad app federated-credential create \
  --id $APP_OBJECT_ID \
  --parameters '{
    "name": "github-lab-env",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:environment:lab",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

</details>

---

## Step 2: Add GitHub Secrets (2 minutes)

1. Go to your GitHub repository
2. Click: **Settings** → **Secrets and variables** → **Actions**
3. Click: **New repository secret**

Add these 4 secrets:

| Secret Name | Value | Where to find it |
|-------------|-------|------------------|
| `AZURE_CLIENT_ID` | (from Step 1 output) | Script output or manual setup |
| `AZURE_TENANT_ID` | `0d9e3fa8-707c-4e1a-8885-aa65b35ad4b5` | Already known |
| `AZURE_SUBSCRIPTION_ID` | `81adc0ae-0abb-443d-9b8b-05cb650a2d46` | Already known |
| `KEY_VAULT_NAME` | `kv-dclab-0119` | Already known |

**Screenshot of where to add secrets:**
```
GitHub Repo → Settings → Secrets and variables → Actions → New repository secret
```

---

## Step 3: Create GitHub Environment (1 minute)

1. Go to: **Settings** → **Environments**
2. Click: **New environment**
3. Name: `lab`
4. Click: **Configure environment**
5. Leave all protection rules disabled (for easy testing)
6. Click: **Save protection rules**

---

## Step 4: Set Up Self-Hosted Runner (Choose One)

### Why do we need this?

GitHub's hosted runners run in **public cloud** and **cannot reach your private DC01** in Azure VNet.

You need a runner that can connect to DC01 (10.0.0.6).

---

### Option A: Use Your Local Machine (Easiest for Testing)

**Best if:** You can already connect to DC01 from your laptop/desktop

#### Test connectivity first:
```powershell
Test-NetConnection 4.234.159.63 -Port 5985
```

If successful ✅, set up runner on your machine:

#### Windows Setup:
1. Go to: `https://github.com/YOUR_ORG/YOUR_REPO/settings/actions/runners/new`
2. Select: **Windows**
3. Download and extract runner
4. Open PowerShell as Administrator:

```powershell
# Navigate to runner folder
cd C:\actions-runner

# Configure (follow prompts)
.\config.cmd --url https://github.com/YOUR_ORG/YOUR_REPO --token YOUR_TOKEN

# Install as service (runs automatically)
.\svc.sh install
.\svc.sh start
```

#### macOS/Linux Setup:
1. Go to: `https://github.com/YOUR_ORG/YOUR_REPO/settings/actions/runners/new`
2. Select: **macOS** or **Linux**
3. Download and extract runner
4. Run in terminal:

```bash
cd ~/actions-runner

# Configure
./config.sh --url https://github.com/YOUR_ORG/YOUR_REPO --token YOUR_TOKEN

# Install as service
sudo ./svc.sh install
sudo ./svc.sh start
```

**Verify:**
- Go to: Settings → Actions → Runners
- You should see your runner with a green dot ✅

---

### Option B: Create Azure VM Runner (Better for Production)

**Best if:** You want a dedicated runner in Azure

#### Quick VM Creation:

```bash
# Create a small Windows VM in same VNet as DC01
az vm create \
  --resource-group VAMDEVTEST \
  --name github-runner \
  --image Win2022Datacenter \
  --size Standard_B2s \
  --admin-username azureuser \
  --admin-password 'ChangeMe123!@#' \
  --vnet-name DC01-vnet \
  --subnet default \
  --public-ip-sku Standard

# Get public IP
az vm show -d --resource-group VAMDEVTEST --name github-runner --query publicIps -o tsv
```

**Then:**
1. RDP into the new VM
2. Follow Option A steps to install runner
3. Test connectivity to DC01:
   ```powershell
   Test-NetConnection 10.0.0.6 -Port 5985
   ```

---

### Option C: Use GitHub-Hosted Runner with Azure Bastion (Advanced)

**Not recommended for lab** - requires additional Azure Bastion setup.

---

## Step 5: Verify Setup ✅

### Check all components:

```bash
# 1. Check DC01 is running
az vm show --resource-group VAMDEVTEST --name DC01 --query "powerState"

# 2. Check Key Vault has secrets
az keyvault secret list --vault-name kv-dclab-0119 --query "[].name" -o tsv

# 3. Check runner is online
# Go to: GitHub → Settings → Actions → Runners
# Should show: ✅ Idle (green)

# 4. Check GitHub secrets
# Go to: GitHub → Settings → Secrets and variables → Actions
# Should have: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, KEY_VAULT_NAME
```

---

## Step 6: Run Your First Test! 🚀

### Via GitHub UI:

1. Go to: **Actions** tab in your repo
2. Select: **"Deploy to Lab"** workflow
3. Click: **"Run workflow"**
4. Enter:
   - **target_dc**: `dc01.linkedin.local`
   - **skip_validation**: Leave unchecked
5. Click: **"Run workflow"** (green button)
6. Watch the progress!

### Via Command Line:

```bash
gh workflow run deploy-lab.yml \
  -f target_dc=dc01.linkedin.local \
  -f skip_validation=false

# Watch it run
gh run watch
```

**Expected duration:** ~30-40 minutes

---

## Troubleshooting

### Runner shows offline ❌

**Check:**
```bash
# On runner machine
systemctl status actions.runner.*  # Linux/macOS
Get-Service -Name "actions.runner.*"  # Windows PowerShell
```

**Restart:**
```bash
sudo ./svc.sh restart  # Linux/macOS
.\svc.cmd restart      # Windows (as Admin)
```

### Workflow fails: "Key Vault access denied"

**Fix:**
```bash
# Re-grant access to Service Principal
APP_ID="<your-client-id>"
SP_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

az keyvault set-policy \
  --name kv-dclab-0119 \
  --object-id $SP_ID \
  --secret-permissions get list
```

### Workflow fails: "Cannot connect to DC01"

**From runner, test:**
```powershell
Test-NetConnection 4.234.159.63 -Port 5985  # Public IP
Test-NetConnection 10.0.0.6 -Port 5985      # Private IP (if in same VNet)
```

**If fails:**
- Check DC01 NSG allows inbound 5985 (WinRM)
- Check DC01 is running: `az vm show -d --resource-group VAMDEVTEST --name DC01`
- Verify WinRM is enabled on DC01

---

## Summary - Complete Checklist

- [ ] Run `setup-azure-app-registration.sh` → Get AZURE_CLIENT_ID
- [ ] Add 4 GitHub secrets (AZURE_CLIENT_ID, TENANT_ID, SUBSCRIPTION_ID, KEY_VAULT_NAME)
- [ ] Create `lab` GitHub environment
- [ ] Set up runner (local machine or Azure VM)
- [ ] Verify runner shows "Idle ✅" in GitHub
- [ ] Run first test: `gh workflow run deploy-lab.yml -f target_dc=dc01.linkedin.local`

---

## What Happens Next?

Once your first lab test succeeds:
1. ✅ You've validated the entire pipeline
2. 🎯 You can replicate for staging environment
3. 🚀 Then deploy to production DCs

**Estimated time to complete this guide:** 15-20 minutes

---

**Need Help?**
- Check: `v2-github-actions/LAB-QUICKSTART.md`
- Review: `v2-github-actions/docs/LAB-SETUP.md`
- Debug: `v2-github-actions/docs/GITHUB-ACTIONS-SETUP.md`
