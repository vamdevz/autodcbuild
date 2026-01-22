# IaaC-v2-main Porting Guide for LinkedIn.local Lab

## 🎯 Purpose

Port the IaaC-v2-main project to your Azure lab environment with `linkedin.local` domain.

**Target Environment:**
- Domain: `linkedin.local`
- Existing DC: `DC01` at `10.100.10.4`
- Resource Group: `VAMDEVTEST`
- VNet: `PurpleCloud-22twg-vnet` (10.100.0.0/16)
- GitHub: `vamdevz/autodcbuild` (or new repo)

---

## 📋 **Environment Neutrality Assessment**

### ✅ **GOOD NEWS: Highly Configurable!**

The project is **well-designed** with clear separation of environment-specific values:

| Component | Configurable | Method |
|-----------|-------------|---------|
| **Domain Name** | ✅ Yes | `terraform.tfvars` |
| **IP Addresses** | ✅ Yes | `terraform.tfvars` |
| **Resource Names** | ✅ Yes | `terraform.tfvars` |
| **Azure Region** | ✅ Yes | `terraform.tfvars` |
| **VM Specs** | ✅ Yes | `terraform.tfvars` |
| **Network Config** | ✅ Yes | `terraform.tfvars` |
| **Credentials** | ✅ Yes | Environment variables or Azure Key Vault |

### ⚠️ **Items Requiring Changes**

| Item | Location | Action Required |
|------|----------|-----------------|
| **Example Domain** | Documentation, examples | Update `contoso.com` → `linkedin.local` |
| **Example IPs** | Documentation, examples | Update `10.0.x.x` → your lab IPs |
| **Resource Group** | `terraform.tfvars` | Update to `VAMDEVTEST` |
| **Existing DC IP** | `terraform.tfvars` | Update to `10.100.10.4` |
| **VNet Config** | `terraform.tfvars` | Match your existing VNet |

---

## 🛠️ **Prerequisites**

### **1. Local Tools Installation**

```bash
# Terraform
brew install terraform
terraform --version  # Should be >= 1.5.0

# Ansible
brew install ansible
ansible --version   # Should be >= 2.14.0

# Ansible Azure Collection
ansible-galaxy collection install azure.azcollection
ansible-galaxy collection install community.windows

# Azure CLI (you already have this)
az --version  # Should be >= 2.50.0

# Git (you already have this)
git --version

# Optional: PowerShell Core (for testing)
brew install powershell/tap/powershell
pwsh --version
```

### **2. Azure Prerequisites**

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "your-subscription-id"
az account show

# Verify access to your resource group
az group show --name VAMDEVTEST

# Verify existing DC
az vm show --resource-group VAMDEVTEST --name DC01
```

### **3. GitHub Setup**

**Option A: Use Existing Repo (vamdevz/autodcbuild)**
```bash
cd "/Volumes/Vamdev Data/Downloads/Projects/autodcbuild"
mkdir -p iaac-v2-terraform
# Copy project files here
```

**Option B: Create New Repo**
```bash
cd "/Volumes/Vamdev Data/Downloads/Projects"
mkdir linkedin-dc-terraform
cd linkedin-dc-terraform
git init
gh repo create linkedin-dc-terraform --private
```

### **4. Required Credentials**

Gather these beforehand:
- ✅ Local Admin Password (for new VMs)
- ✅ Domain Admin Password (`linkedin\vamdev` - you already have this)
- ✅ DSRM Password (can be same as domain admin for lab)

---

## 📁 **Project Structure Analysis**

```
IaaC-v2-main/
├── terraform/
│   ├── modules/               # ✅ Reusable, no changes needed
│   │   ├── networking/
│   │   ├── compute/
│   │   ├── security/
│   │   ├── bastion/
│   │   └── monitoring/
│   │
│   └── environments/
│       ├── production/        # 🔧 Main deployment (modify)
│       ├── existing-vm-promotion/  # 🔧 For your use case!
│       ├── staging/
│       └── dc-demote/
│
├── ansible/
│   ├── playbooks/            # ✅ No changes needed
│   ├── roles/                # ✅ No changes needed
│   ├── inventory/            # 🔧 Update for your environment
│   └── group_vars/           # 🔧 Update domain/IPs
│
├── .github/
│   └── workflows/            # 🔧 GitHub Actions (optional)
│
├── deployments/              # 🔧 GitOps YAML files
│   ├── requests/
│   └── templates/
│
└── docs/                     # ℹ️  Reference only
```

**Key Insight:** Modules are environment-agnostic. Only need to modify:
- `terraform/environments/*/terraform.tfvars`
- `ansible/group_vars/` and `inventory/`
- `deployments/` YAML files

---

## 🚀 **Step-by-Step Porting Instructions**

### **Phase 1: Copy and Setup Project**

#### **Step 1.1: Copy Project to Your Workspace**

```bash
# Navigate to your projects folder
cd "/Volumes/Vamdev Data/Downloads/Projects"

# Copy the friend's project
cp -r autodcbuild/IaaC-v2-main linkedin-dc-terraform

# Navigate into new project
cd linkedin-dc-terraform

# Initialize git (if new repo)
git init
git add .
git commit -m "chore: initial import of IaaC-v2-main for linkedin.local lab"

# Link to GitHub (if new repo)
gh repo create linkedin-dc-terraform --private --source=.
git push -u origin main
```

#### **Step 1.2: Clean Up Examples (Optional)**

```bash
# Remove example deployment requests
rm -rf deployments/requests/DC*.yaml

# Keep only templates
ls deployments/templates/
# Should show: dc-deployment.yaml, dc-demote.yaml
```

---

### **Phase 2: Configure Terraform for Your Environment**

#### **Step 2.1: Choose Deployment Method**

**For Your Lab, I recommend: `existing-vm-promotion`**

This matches your use case:
- ✅ You have existing VMs
- ✅ You have existing DC01 (10.100.10.4)
- ✅ You want to promote additional DCs to linkedin.local

```bash
cd terraform/environments/existing-vm-promotion
```

#### **Step 2.2: Create Your terraform.tfvars**

```bash
# Copy example
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
code terraform.tfvars  # or vi, nano, etc.
```

**Your `terraform.tfvars` file:**

```hcl
# =============================================================================
# LinkedIn.local Lab - DC Promotion Configuration
# =============================================================================

# Existing VM to promote
existing_vm_resource_group = "VAMDEVTEST"
existing_vm_name           = "windows11VM"  # Or create a new VM first

# Domain configuration
domain_name           = "linkedin.local"
domain_admin_username = "vamdev"  # NOT linkedin\vamdev, just username

# Existing DC for DNS
existing_dc_ip = "10.100.10.4"  # Your DC01

# Optional settings
install_dns = true
site_name   = "Default-First-Site-Name"

# Tags (optional but recommended)
tags = {
  Environment = "Lab"
  Project     = "LinkedIn DC Infrastructure"
  ManagedBy   = "Terraform"
  Owner       = "vamishra"
}

# =============================================================================
# Passwords - Set via environment variables:
# export TF_VAR_domain_admin_password='Sarita123@@@'
# export TF_VAR_dsrm_password='Sarita123@@@'
# =============================================================================
```

#### **Step 2.3: Set Environment Variables**

```bash
# Set credentials
export TF_VAR_domain_admin_password='Sarita123@@@'
export TF_VAR_dsrm_password='Sarita123@@@'

# Verify
echo "Domain Admin Password set: ${TF_VAR_domain_admin_password:+YES}"
echo "DSRM Password set: ${TF_VAR_dsrm_password:+YES}"

# Optional: Add to your ~/.zshrc for persistence
cat >> ~/.zshrc << 'EOF'

# LinkedIn Lab Terraform Credentials
export TF_VAR_domain_admin_password='Sarita123@@@'
export TF_VAR_dsrm_password='Sarita123@@@'
EOF
```

#### **Step 2.4: Initialize Terraform**

```bash
# Still in terraform/environments/existing-vm-promotion/
terraform init

# Should see:
# Terraform has been successfully initialized!
```

#### **Step 2.5: Validate Configuration**

```bash
# Check syntax
terraform validate

# Plan deployment (dry-run)
terraform plan

# Review output:
# - Should show it will promote the VM to DC
# - Check that domain name is linkedin.local
# - Check that DC IP is 10.100.10.4
```

---

### **Phase 3: Configure Ansible (If Using Option 2 or 3)**

#### **Step 3.1: Update Ansible Inventory**

```bash
cd ../../ansible/inventory

# Create your inventory file
cp existing_domain_hosts.yml linkedin_lab_hosts.yml

# Edit
code linkedin_lab_hosts.yml
```

**Your `linkedin_lab_hosts.yml`:**

```yaml
# =============================================================================
# LinkedIn.local Lab Inventory
# =============================================================================

all:
  vars:
    # Domain Configuration
    ad_domain_name: "linkedin.local"
    ad_domain_netbios_name: "LINKEDIN"
    
    # Existing DC
    existing_dc_ip: "10.100.10.4"
    
    # WinRM Settings
    ansible_connection: winrm
    ansible_port: 5985
    ansible_winrm_transport: ntlm
    ansible_winrm_server_cert_validation: ignore
    ansible_user: azureadmin  # Or your VM's local admin
    # ansible_password: Set via Ansible Vault

  children:
    domain_controllers:
      hosts:
        dc01:
          ansible_host: 10.100.10.4
          dc_hostname: "DC01"
          dc_description: "Primary DC - Existing"
          
        new-dc02:
          ansible_host: 10.100.10.5  # Or your target IP
          dc_hostname: "DC02"
          dc_description: "Secondary DC - New"
```

#### **Step 3.2: Update Group Variables**

```bash
cd ../group_vars

# Edit all.yml
code all.yml
```

**Update these lines in `all.yml`:**

```yaml
# Change from:
ad_domain_name: "corp.contoso.com"
ad_domain_netbios_name: "CORP"

# To:
ad_domain_name: "linkedin.local"
ad_domain_netbios_name: "LINKEDIN"
```

#### **Step 3.3: Create Ansible Vault**

```bash
# Copy example
cp vault.yml.example vault.yml

# Edit with your passwords
vi vault.yml
```

**Your `vault.yml`:**

```yaml
# LinkedIn Lab Credentials
vault_admin_password: "YourLocalAdminPassword"  # For local admin on VMs
vault_domain_admin_password: "Sarita123@@@"     # Your domain admin password
vault_dsrm_password: "Sarita123@@@"             # DSRM password
```

**Encrypt the vault:**

```bash
# Encrypt
ansible-vault encrypt vault.yml
# Enter password: (choose a strong vault password)

# Verify
cat vault.yml
# Should show: $ANSIBLE_VAULT;1.1;AES256...

# Create password file for convenience
echo "your_vault_password" > .vault_pass
chmod 600 .vault_pass

# Add to .gitignore
echo ".vault_pass" >> ../../.gitignore
```

---

### **Phase 4: Update Documentation (Recommended)**

#### **Step 4.1: Update README.md**

```bash
cd ../..
code README.md
```

**Search and replace:**
- `contoso.com` → `linkedin.local`
- `corp.contoso.com` → `linkedin.local`
- `10.100.10.4` → Keep (it's correct!)
- `dc1` → `DC01` (your existing DC)

**Update deployment status table:**

```markdown
| Domain | DCs Deployed | Status |
|--------|--------------|--------|
| `linkedin.local` | 2 (1 existing + 1 new) | ✅ **Operational** |

### Domain Controllers

| DC Name | IP Address | Location | Role |
|---------|------------|----------|------|
| DC01 (existing) | `10.100.10.4` | VAMDEVTEST | Primary DC |
| DC02 (new) | `10.100.10.5` | VAMDEVTEST | Replica DC |
```

#### **Step 4.2: Update Deployment Templates**

```bash
cd deployments/templates
code dc-deployment.yaml
```

**Update examples:**

```yaml
# Change example IPs and domain:
  ip_address: "10.100.10.5"              # Your lab subnet
  domain_name: "linkedin.local"           # Your domain
  domain_netbios_name: "LINKEDIN"         # Your NetBIOS
  existing_dc_ip: "10.100.10.4"          # Your DC01
```

---

### **Phase 5: Test Deployment**

#### **Step 5.1: Pre-Flight Checks**

```bash
# Verify Azure connection
az account show

# Verify existing DC is reachable
az vm show --resource-group VAMDEVTEST --name DC01

# Verify DNS from DC01
# (Login to DC01 and check it's responding to DNS queries)

# Verify credentials are set
env | grep TF_VAR
```

#### **Step 5.2: Terraform Deployment (Dry Run)**

```bash
cd terraform/environments/existing-vm-promotion

# Plan (doesn't make changes)
terraform plan -out=tfplan

# Review the plan carefully:
# - VM name correct?
# - Domain name linkedin.local?
# - DC IP 10.100.10.4?
```

#### **Step 5.3: Execute Deployment**

```bash
# Apply the plan
terraform apply tfplan

# This will:
# 1. Install AD DS role on the VM
# 2. Configure DNS to point to DC01
# 3. Promote VM to DC in linkedin.local domain
# 4. Reboot the VM
# 5. Wait for DC services to start

# Monitor output for any errors
# Expected time: 15-30 minutes
```

#### **Step 5.4: Verify Deployment**

```bash
# Check Terraform outputs
terraform output

# Should show:
# - VM name
# - Status: Successfully promoted
# - Domain: linkedin.local

# RDP to the new DC and verify:
# 1. Open "Active Directory Users and Computers"
# 2. Verify domain is linkedin.local
# 3. Check replication: Get-ADReplicationPartnerMetadata -Target *
# 4. Verify DNS: nslookup linkedin.local
```

---

### **Phase 6: Optional - Ansible Post-Configuration**

**If you want to add enterprise features (OUs, policies, etc.):**

```bash
cd ../../../ansible

# Test connection
ansible -i inventory/linkedin_lab_hosts.yml all -m ansible.windows.win_ping --ask-vault-pass

# Run post-installation playbook
ansible-playbook -i inventory/linkedin_lab_hosts.yml \
  playbooks/site.yml \
  --tags="post-install,security" \
  --ask-vault-pass

# Or with vault password file
ansible-playbook -i inventory/linkedin_lab_hosts.yml \
  playbooks/site.yml \
  --tags="post-install" \
  --vault-password-file=.vault_pass
```

---

### **Phase 7: GitHub Integration (Optional)**

#### **Step 7.1: Add GitHub Actions Workflow**

```bash
mkdir -p .github/workflows
```

**Create `.github/workflows/terraform-plan.yml`:**

```yaml
name: Terraform Plan

on:
  pull_request:
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-plan.yml'

jobs:
  plan:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.0
      
      - name: Terraform Init
        working-directory: terraform/environments/existing-vm-promotion
        run: terraform init
      
      - name: Terraform Validate
        working-directory: terraform/environments/existing-vm-promotion
        run: terraform validate
      
      - name: Terraform Plan
        working-directory: terraform/environments/existing-vm-promotion
        env:
          TF_VAR_domain_admin_password: ${{ secrets.DOMAIN_ADMIN_PASSWORD }}
          TF_VAR_dsrm_password: ${{ secrets.DSRM_PASSWORD }}
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
        run: terraform plan -no-color
```

#### **Step 7.2: Add GitHub Secrets**

```bash
# Add secrets via GitHub CLI
gh secret set DOMAIN_ADMIN_PASSWORD --body "Sarita123@@@"
gh secret set DSRM_PASSWORD --body "Sarita123@@@"

# Azure credentials (if using service principal)
gh secret set AZURE_CLIENT_ID --body "your-client-id"
gh secret set AZURE_CLIENT_SECRET --body "your-client-secret"
gh secret set AZURE_SUBSCRIPTION_ID --body "your-subscription-id"
gh secret set AZURE_TENANT_ID --body "your-tenant-id"
```

---

## 📊 **Configuration Reference**

### **Your Environment Values**

| Parameter | Value | Location |
|-----------|-------|----------|
| **Domain Name** | `linkedin.local` | `terraform.tfvars` |
| **Domain NetBIOS** | `LINKEDIN` | `terraform.tfvars`, `group_vars/all.yml` |
| **Existing DC** | `DC01` at `10.100.10.4` | `terraform.tfvars` |
| **Resource Group** | `VAMDEVTEST` | `terraform.tfvars` |
| **VNet** | `PurpleCloud-22twg-vnet` | Existing (no changes) |
| **Subnet** | `10.100.10.0/24` | Existing (no changes) |
| **Domain Admin** | `vamdev` | `terraform.tfvars` |
| **Domain Admin Password** | `Sarita123@@@` | Environment variable |
| **DSRM Password** | `Sarita123@@@` | Environment variable |

---

### **Files to Modify - Checklist**

**Terraform:**
- ✅ `terraform/environments/existing-vm-promotion/terraform.tfvars`
  - existing_vm_resource_group = "VAMDEVTEST"
  - domain_name = "linkedin.local"
  - existing_dc_ip = "10.100.10.4"

**Ansible (if used):**
- ✅ `ansible/inventory/linkedin_lab_hosts.yml` (create new)
- ✅ `ansible/group_vars/all.yml`
  - ad_domain_name: "linkedin.local"
  - ad_domain_netbios_name: "LINKEDIN"
- ✅ `ansible/group_vars/vault.yml` (create and encrypt)

**Documentation:**
- ✅ `README.md` - Update examples
- ✅ `deployments/templates/*.yaml` - Update examples

**Keep As-Is:**
- ✅ `terraform/modules/` - No changes needed
- ✅ `ansible/roles/` - No changes needed
- ✅ `ansible/playbooks/` - No changes needed

---

## 🐛 **Troubleshooting**

### **Issue 1: Terraform Init Fails**

```bash
# Error: Failed to initialize providers

# Solution: Check Terraform version
terraform --version  # Must be >= 1.5.0

# Solution: Clear cache and retry
rm -rf .terraform .terraform.lock.hcl
terraform init
```

### **Issue 2: Azure Authentication Fails**

```bash
# Error: Unable to authenticate

# Solution: Re-login
az logout
az login
az account set --subscription "your-subscription-id"
```

### **Issue 3: VM Promotion Fails - DNS**

```bash
# Error: Cannot resolve domain

# Solution: Check existing DC is reachable
az vm show --resource-group VAMDEVTEST --name DC01 --query "powerState"
# Should show: VM running

# Test connectivity
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name windows11VM \
  --command-id RunPowerShellScript \
  --scripts "Test-NetConnection -ComputerName 10.100.10.4 -Port 389"
```

### **Issue 4: Ansible Vault Password Error**

```bash
# Error: Incorrect vault password

# Solution: Verify vault password file
cat .vault_pass  # Check password is correct

# Or decrypt and re-encrypt
ansible-vault decrypt group_vars/vault.yml
ansible-vault encrypt group_vars/vault.yml
```

### **Issue 5: WinRM Connection Fails**

```bash
# Error: Ansible cannot connect

# Solution: Ensure WinRM is enabled on target VM
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name windows11VM \
  --command-id RunPowerShellScript \
  --scripts "Enable-PSRemoting -Force; winrm quickconfig -force"

# Check firewall
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name windows11VM \
  --command-id RunPowerShellScript \
  --scripts "Test-NetConnection -ComputerName localhost -Port 5985"
```

---

## ✅ **Validation Checklist**

After porting, verify:

**Terraform:**
- [ ] `terraform init` completes successfully
- [ ] `terraform validate` passes
- [ ] `terraform plan` shows correct domain name (linkedin.local)
- [ ] `terraform plan` shows correct DC IP (10.100.10.4)
- [ ] Environment variables are set (TF_VAR_*)

**Ansible (if used):**
- [ ] Ansible vault is created and encrypted
- [ ] Inventory file has correct IPs
- [ ] `ansible -m ping` works
- [ ] Group vars have linkedin.local domain

**Documentation:**
- [ ] README updated with your environment
- [ ] Examples show linkedin.local (not contoso.com)
- [ ] Deployment templates updated

**Deployment:**
- [ ] VM promotes to DC successfully
- [ ] DC appears in Active Directory Sites and Services
- [ ] Replication works (Get-ADReplicationPartnerMetadata)
- [ ] DNS works (nslookup linkedin.local)

---

## 🎯 **Next Steps After Porting**

1. **Test in Lab:**
   - Deploy a test DC promotion
   - Verify all features work
   - Document any issues

2. **Customize Further:**
   - Add your OUs structure
   - Configure password policies
   - Add security hardening

3. **Integrate with Your Workflow:**
   - Add to your GitHub repo
   - Set up CI/CD pipeline
   - Create runbooks

4. **Share Knowledge:**
   - Document your changes
   - Create team training
   - Establish best practices

---

## 📚 **Additional Resources**

**Terraform:**
- [Terraform Azure Provider Docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

**Ansible:**
- [Ansible Windows Guide](https://docs.ansible.com/ansible/latest/os_guide/windows_usage.html)
- [Ansible Azure Collection](https://docs.ansible.com/ansible/latest/collections/azure/azcollection/)

**Active Directory:**
- [Install-ADDSDomainController](https://learn.microsoft.com/en-us/powershell/module/addsdeployment/install-addsdomaincontroller)
- [AD Replication Guide](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/replication/active-directory-replication-concepts)

---

## 🎉 **Summary**

**Environment Neutrality: ✅ EXCELLENT**

The IaaC-v2-main project is **highly environment-neutral**:
- ✅ All environment-specific values in config files
- ✅ No hardcoded credentials
- ✅ Modular architecture (reusable modules)
- ✅ Clear separation of concerns
- ✅ Well-documented configuration options

**Porting Effort: MODERATE**

- **Time Estimate:** 2-4 hours for initial setup
- **Complexity:** Medium (mostly configuration changes)
- **Risk:** Low (good rollback options with Terraform)

**Recommendation: GO FOR IT!**

The project is well-suited for porting to your environment. The main work is configuration, not code changes.

---

*Porting Guide Version: 1.0*  
*Date: January 20, 2026*  
*Target: LinkedIn.local Lab Environment*
