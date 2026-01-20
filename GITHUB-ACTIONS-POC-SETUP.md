# GitHub Actions CI/CD Setup - POC (No OIDC Required)

**Perfect for POC testing when you don't have Azure AD admin permissions.**

This setup uses:
- ✅ GitHub-hosted runners (can reach DC01 public IP)
- ✅ GitHub secrets (no Azure Key Vault needed for POC)
- ✅ Simplified workflow (no OIDC/App Registration)
- ✅ Full CI/CD automation

---

## Prerequisites

✅ Already have:
- [x] DC01 running with public IP (4.234.159.63)
- [x] WinRM open (port 5985)
- [x] Credentials (linkedin\vamdev)

---

## Step 1: Push Code to GitHub (2 minutes)

If you haven't already:

```bash
cd '/Volumes/Vamdev Data/Downloads/Projects/LinkedIn - DC IaaC Build'

# Initialize git (if needed)
git remote -v

# If no remote, add your GitHub repo
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git

# Push code
git push -u origin main
# or
git push -u origin v1-stable
```

---

## Step 2: Add GitHub Secrets (2 minutes)

1. Go to your GitHub repository
2. Click: **Settings** → **Secrets and variables** → **Actions**
3. Click: **New repository secret**

Add these **3 secrets**:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `DOMAIN_ADMIN_USERNAME` | `linkedin\vamdev` | Domain admin username |
| `DOMAIN_ADMIN_PASSWORD` | `Sarita123@@@` | Domain admin password |
| `SAFE_MODE_PASSWORD` | `Sarita123@@@` | Safe mode (DSRM) password |

### Screenshots:

**Navigate to Secrets:**
```
Your Repo → Settings (top menu)
  → Secrets and variables (left sidebar)
    → Actions
      → New repository secret (green button)
```

**For each secret:**
1. Name: Copy from table above
2. Secret: Paste the value
3. Click: Add secret

---

## Step 3: Run Your First Deployment (2 minutes to start, 40 min automated)

### Via GitHub UI (Easiest):

1. Go to your repository on GitHub
2. Click the **Actions** tab
3. Select: **"Deploy to Lab (Simple - No OIDC)"** from the left sidebar
4. Click: **"Run workflow"** (right side, blue button)
5. Configure:
   - **Use workflow from**: `main` or `v1-stable` (your branch)
   - **Target DC IP or hostname**: `4.234.159.63`
   - **Skip pre-promotion checks**: ☐ Leave unchecked
6. Click: **"Run workflow"** (green button)

### Via GitHub CLI:

```bash
# Run the workflow
gh workflow run deploy-lab-simple.yml \
  -f target_dc=4.234.159.63 \
  -f skip_validation=false

# Watch it run in real-time
gh run watch

# Or view the run
gh run list --workflow=deploy-lab-simple.yml
gh run view <RUN_ID> --log
```

---

## Step 4: Monitor Progress

### In GitHub UI:

1. Click on the workflow run (it appears immediately)
2. Click on the **"deploy"** job
3. Expand each step to see live logs
4. Watch the progress:
   - ✅ Test connectivity
   - ✅ Phase 1: Pre-checks
   - ✅ Phase 2: DC Promotion (~20 min)
   - ✅ Phase 3: Post-Configuration

### What Happens:

```
┌─────────────────────────────────────────────┐
│ GitHub-hosted Runner (Ubuntu)               │
│   ↓                                         │
│ 1. Checkout code                            │
│ 2. Install PowerShell modules               │
│ 3. Test connectivity to 4.234.159.63:5985   │
│ 4. Run DC Promotion Pipeline:               │
│    ├─ Pre-checks (domain, DNS, disk)        │
│    ├─ Install AD DS role                    │
│    ├─ Promote to DC (dcpromo)               │
│    ├─ Reboot & wait for services            │
│    ├─ Health validation (7 tests)           │
│    └─ Post-configuration                    │
│ 5. Show deployment summary                  │
└─────────────────────────────────────────────┘
```

---

## Expected Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| **Setup** | ~2 min | Install modules, test connectivity |
| **Pre-checks** | ~2 min | Validate server readiness |
| **DC Promotion** | ~15 min | Install AD DS, run dcpromo |
| **Reboot** | ~5 min | System restart, service startup |
| **Health Checks** | ~8 min | 7 comprehensive validation tests |
| **Post-Config** | ~5 min | DNS, reporting (agents skipped in lab) |
| **Total** | ~37 min | End-to-end automated |

---

## Troubleshooting

### Workflow fails: "Cannot reach WinRM port 5985"

**Check DC01 is running:**
```bash
az vm show --resource-group VAMDEVTEST --name DC01 --query "powerState"
```

**Start DC01 if stopped:**
```bash
az vm start --resource-group VAMDEVTEST --name DC01
```

**Verify NSG rule:**
```bash
az network nsg rule show \
  --resource-group VAMDEVTEST \
  --nsg-name DC01-nsg \
  --name winrm_allow
```

### Workflow fails: "Authentication failed"

**Check secrets are set correctly:**
1. Go to: Settings → Secrets → Actions
2. Verify all 3 secrets exist:
   - DOMAIN_ADMIN_USERNAME
   - DOMAIN_ADMIN_PASSWORD
   - SAFE_MODE_PASSWORD
3. Re-create them if needed (secrets can't be viewed, only replaced)

### Workflow fails: "Pre-checks failed"

**Common issues:**
- **Domain membership**: Expected if DC01 is not yet a DC
- **DC connectivity**: Expected if no existing DC to connect to
- **Disk space**: Check DC01 has 20GB+ free

**Skip pre-checks for first DC:**
```bash
gh workflow run deploy-lab-simple.yml \
  -f target_dc=4.234.159.63 \
  -f skip_validation=true
```

### Workflow gets stuck

**Cancel and re-run:**
1. Go to Actions → Click the running workflow
2. Click: Cancel workflow
3. Fix the issue (restart DC01, check secrets, etc.)
4. Re-run: Click "Re-run all jobs"

---

## Verify Deployment

After successful completion, verify on DC01:

### Option 1: Via RDP

```powershell
# RDP to 4.234.159.63

# Check DC role
Get-ADDomainController -Identity DC01

# Check services
Get-Service NTDS, DNS, Netlogon, W32Time, KDC

# Run diagnostics
dcdiag /v

# Check replication (if multiple DCs)
repadmin /showrepl
```

### Option 2: Via WinRM (from your machine)

```powershell
# Create credential
$password = ConvertTo-SecureString "Sarita123@@@" -AsPlainText -Force
$cred = New-Object PSCredential("linkedin\vamdev", $password)

# Connect
$session = New-PSSession -ComputerName 4.234.159.63 -Credential $cred

# Run commands
Invoke-Command -Session $session -ScriptBlock {
    Get-ADDomainController -Identity DC01
    Get-Service NTDS, DNS, Netlogon
}

# Disconnect
Remove-PSSession $session
```

---

## What's Different from Full Setup?

| Feature | POC Setup | Full Production Setup |
|---------|-----------|----------------------|
| **Authentication** | GitHub secrets | Azure Key Vault + OIDC |
| **Runner** | GitHub-hosted | Self-hosted in Azure VNet |
| **DC Access** | Public IP | Private IP via VNet |
| **Approval** | None | Required for production |
| **Security** | Basic | Enterprise-grade |
| **Cost** | Free (GitHub Actions) | Minimal (runner VM + Key Vault) |

---

## Upgrade to Production Later

Once POC is validated, upgrade to full security:

1. **Get Azure AD admin to create App Registration**
2. **Deploy self-hosted runner in Azure VNet**
3. **Switch to Azure Key Vault for secrets**
4. **Close public WinRM access**
5. **Use private IPs only**
6. **Add approval gates for production**

See: `GITHUB-SETUP-GUIDE.md` for full production setup.

---

## Security Considerations for POC

⚠️ **This is a POC/testing setup. For production:**

**Current security risks:**
- DC01 WinRM open to internet (port 5985)
- Credentials in GitHub secrets (less secure than Key Vault)
- No approval gates
- No audit trail in Azure

**Acceptable for:**
- ✅ Lab/testing environment
- ✅ POC validation
- ✅ Learning the pipeline

**NOT acceptable for:**
- ❌ Production domain controllers
- ❌ Corporate environments
- ❌ Compliance-required systems

**Mitigation for POC:**
- Use isolated lab domain (linkedin.local)
- Use test credentials
- Close DC01 when not testing
- Monitor GitHub Actions logs
- Delete secrets when done

---

## Cost of Running This POC

**GitHub Actions:**
- Free tier: 2,000 minutes/month
- This workflow: ~40 minutes per run
- **Cost**: $0 (within free tier)

**Azure Resources:**
- DC01 VM running: ~$0.10/hour
- DC01 VM stopped (deallocated): $0/hour (only storage ~$5/month)
- Key Vault: ~$0 (minimal operations)

**Total POC cost**: < $1/day if you stop DC01 between tests

---

## Quick Reference Commands

```bash
# Start DC01
az vm start --resource-group VAMDEVTEST --name DC01

# Run deployment
gh workflow run deploy-lab-simple.yml -f target_dc=4.234.159.63

# Watch progress
gh run watch

# Stop DC01 (save costs)
az vm deallocate --resource-group VAMDEVTEST --name DC01

# View deployment logs
gh run list --workflow=deploy-lab-simple.yml
gh run view --log
```

---

## Summary - Complete Checklist

Setup (5 minutes):
- [ ] Push code to GitHub repository
- [ ] Add 3 GitHub secrets (credentials)
- [ ] Ensure DC01 is running

Run (2 minutes to start):
- [ ] Go to Actions tab
- [ ] Select "Deploy to Lab (Simple - No OIDC)"
- [ ] Click "Run workflow"
- [ ] Enter target DC: 4.234.159.63
- [ ] Click "Run workflow" button

Wait (~40 minutes):
- [ ] Monitor progress in GitHub Actions
- [ ] Check for any errors
- [ ] Wait for completion

Verify (5 minutes):
- [ ] RDP to DC01
- [ ] Run dcdiag
- [ ] Verify AD services

---

**You're ready! Go to GitHub Actions and run your first deployment.** 🚀

**Questions?** Check the logs in GitHub Actions for detailed error messages.
