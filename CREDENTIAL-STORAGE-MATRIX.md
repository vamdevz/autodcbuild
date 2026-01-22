# Credential Storage & Usage Matrix

## 🎯 **Your Questions Answered:**

### **Question 1: Are credentials stored in ALL those places?**
**Answer: NO! You choose ONE storage method.**

### **Question 2: Where do credentials come from for each DC promotion option?**
**Answer: Depends on which option you choose!**

---

## 📊 **PART 1: Credential Storage - Choose ONE Method**

### **You DON'T Store Credentials Everywhere!**

```
❌ WRONG ASSUMPTION:
   Credentials are stored in:
   - Azure Key Vault AND
   - Ansible Vault AND
   - Environment variables AND
   - Terraform variables
   (All at the same time)

✅ CORRECT REALITY:
   You CHOOSE ONE storage method:
   - Azure Key Vault (production recommended)
   OR
   - Ansible Vault (if you prefer Ansible)
   OR
   - Environment variables (testing/POC only)
```

---

## 🗂️ **Credential Storage Options (Pick ONE)**

### **Option A: Azure Key Vault (Production - Recommended)**

```yaml
Location: Azure Cloud (managed service)
Created by: Terraform
Used by: Terraform, Ansible (can read from it)
Rotation: Automated via Azure policies
Cost: ~$0.03/10,000 operations

Storage Structure:
  Azure Key Vault: ad-prod-kv-xyz
  ├─ admin-password: "LocalAdmin123!"
  ├─ domain-admin-password: "DomainAdmin456!"
  └─ dsrm-password: "DSRM789!"
```

**How it works:**

```hcl
# Terraform stores secrets when creating VMs
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "admin-password"
  value        = var.admin_password  # From TF_VAR_admin_password env var
  key_vault_id = azurerm_key_vault.main.id
}

# Later, Terraform reads from Key Vault
data "azurerm_key_vault_secret" "admin_password" {
  name         = "admin-password"
  key_vault_id = azurerm_key_vault.main.id
}

# Use in VM creation
resource "azurerm_windows_virtual_machine" "dc" {
  admin_password = data.azurerm_key_vault_secret.admin_password.value
}
```

**Initial Load (One-Time):**
```bash
# You provide credentials ONCE via environment variables
export TF_VAR_admin_password="LocalAdmin123!"
export TF_VAR_domain_admin_password="DomainAdmin456!"
export TF_VAR_dsrm_password="DSRM789!"

# Terraform stores them in Key Vault
terraform apply
# After this, credentials live in Azure Key Vault
# Environment variables are no longer needed
```

**Pros:**
- ✅ Centralized, cloud-managed
- ✅ Automatic encryption
- ✅ Audit logs for access
- ✅ Works with both Terraform and Ansible
- ✅ Supports automatic rotation

**Cons:**
- ⚠️ Requires Azure subscription
- ⚠️ Costs money (minimal)
- ⚠️ Requires proper IAM setup

---

### **Option B: Ansible Vault (Ansible-First Approach)**

```yaml
Location: Local file (encrypted)
Created by: You (manually)
Used by: Ansible only
Rotation: Manual
Cost: Free

Storage Structure:
  ansible/group_vars/vault.yml (encrypted with AES256)
  ├─ vault_admin_password: "LocalAdmin123!"
  ├─ vault_domain_admin_password: "DomainAdmin456!"
  └─ vault_dsrm_password: "DSRM789!"
```

**How it works:**

```bash
# 1. Create vault file
cd ansible
cp group_vars/vault.yml.example group_vars/vault.yml

# 2. Edit with your passwords
vi group_vars/vault.yml
# vault_admin_password: "LocalAdmin123!"
# vault_domain_admin_password: "DomainAdmin456!"
# vault_dsrm_password: "DSRM789!"

# 3. Encrypt the file
ansible-vault encrypt group_vars/vault.yml
# Enter password: my_vault_master_password

# 4. File is now encrypted
cat group_vars/vault.yml
# $ANSIBLE_VAULT;1.1;AES256
# 3533626665663...
```

**Using it:**
```bash
# Run playbook (prompts for vault password)
ansible-playbook playbooks/site.yml --ask-vault-pass

# Or use password file
echo "my_vault_master_password" > .vault_pass
chmod 600 .vault_pass
ansible-playbook playbooks/site.yml --vault-password-file=.vault_pass
```

**Pros:**
- ✅ Free
- ✅ No cloud dependency
- ✅ Simple for Ansible-only workflows

**Cons:**
- ⚠️ Terraform can't read Ansible Vault
- ⚠️ Manual encryption/decryption
- ⚠️ Need to protect .vault_pass file
- ⚠️ Manual rotation

---

### **Option C: Environment Variables (Testing/POC Only)**

```yaml
Location: Shell environment
Created by: You (export commands)
Used by: Terraform, Ansible (via lookup)
Rotation: Manual
Cost: Free

Storage Structure:
  Shell session:
  ├─ TF_VAR_admin_password="LocalAdmin123!"
  ├─ TF_VAR_domain_admin_password="DomainAdmin456!"
  ├─ TF_VAR_dsrm_password="DSRM789!"
  └─ ADMIN_PASSWORD="LocalAdmin123!" (for Ansible)
```

**How it works:**

```bash
# Set in your shell
export TF_VAR_admin_password="LocalAdmin123!"
export TF_VAR_domain_admin_password="DomainAdmin456!"
export TF_VAR_dsrm_password="DSRM789!"

# Terraform automatically reads TF_VAR_ variables
terraform apply  # Uses TF_VAR_admin_password

# Ansible can read from environment
ansible-playbook playbooks/site.yml
# In playbook:
# admin_password: "{{ lookup('env', 'TF_VAR_admin_password') }}"
```

**Pros:**
- ✅ Fastest for testing
- ✅ No setup required
- ✅ Works with both Terraform and Ansible

**Cons:**
- ❌ Lost when shell closes
- ❌ Visible in process list
- ❌ No encryption
- ❌ Not suitable for production
- ❌ No audit trail

---

## 📋 **PART 2: Credential Flow for 3 DC Promotion Options**

### **Option 1: Terraform ONLY (Default)**

**What happens:** Terraform creates VMs + promotes to DC

**Credential Storage:** Azure Key Vault (recommended) OR Environment Variables

**Credential Flow:**

```
┌─────────────────────────────────────────────────────────┐
│  OPTION 1: TERRAFORM ONLY                                │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. INITIAL SETUP (One-Time):                            │
│     ├─ You provide credentials:                          │
│     │  export TF_VAR_admin_password="LocalAdmin123!"     │
│     │  export TF_VAR_domain_admin_password="DomainAdmin456!" │
│     │  export TF_VAR_dsrm_password="DSRM789!"            │
│     │                                                     │
│     └─ Terraform stores in Azure Key Vault:              │
│        az keyvault secret set --vault-name ad-kv \       │
│          --name admin-password --value "LocalAdmin123!"  │
│                                                          │
│  2. VM CREATION:                                         │
│     ├─ Terraform reads from Key Vault                    │
│     ├─ Creates VM: azureadmin:LocalAdmin123!             │
│     └─ Enables WinRM                                     │
│                                                          │
│  3. DC PROMOTION:                                        │
│     ├─ Terraform reads from Key Vault:                   │
│     │  - admin_password                                  │
│     │  - domain_admin_password                           │
│     │  - dsrm_password                                   │
│     │                                                     │
│     └─ Runs azurerm_virtual_machine_run_command:         │
│        PowerShell script with credentials:               │
│        Install-ADDSDomainController \                    │
│          -Credential (PSCredential with domain admin) \  │
│          -SafeModeAdministratorPassword $dsrmPass        │
│                                                          │
│  RESULT: ✅ DC promoted by Terraform                     │
│  ANSIBLE USED: ❌ NO                                      │
│                                                          │
└─────────────────────────────────────────────────────────┘

Credentials Stored: Azure Key Vault (created by Terraform)
Credentials Used By: Terraform only
Ansible Vault: NOT created, NOT used
```

**Commands:**

```bash
# Step 1: Provide credentials (one-time)
export TF_VAR_admin_password="LocalAdmin123!"
export TF_VAR_domain_admin_password="DomainAdmin456!"
export TF_VAR_dsrm_password="DSRM789!"

# Step 2: Terraform does everything
cd terraform/environments/production
terraform init
terraform apply

# Terraform:
# - Reads from TF_VAR_ environment variables
# - Stores in Azure Key Vault
# - Creates VMs
# - Promotes to DC (using creds from Key Vault)
# - Done!

# No Ansible commands needed
```

**Where Credentials Come From:**
- **Initial load**: Environment variables (TF_VAR_*)
- **Runtime**: Azure Key Vault (Terraform reads from it)
- **Ansible Vault**: Not used in this option

---

### **Option 2: Terraform (Infra) + Ansible (DC Promotion)**

**What happens:** Terraform creates VMs, Ansible promotes to DC

**Credential Storage:** Ansible Vault (recommended for this approach)

**Credential Flow:**

```
┌─────────────────────────────────────────────────────────┐
│  OPTION 2: TERRAFORM + ANSIBLE (ALTERNATIVE)             │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. TERRAFORM (VM Creation Only):                        │
│     ├─ You provide credentials:                          │
│     │  export TF_VAR_admin_password="LocalAdmin123!"     │
│     │                                                     │
│     ├─ Set promote_to_dc = false (skip DC promotion)     │
│     │                                                     │
│     └─ Terraform:                                        │
│        ├─ Creates VMs: azureadmin:LocalAdmin123!         │
│        ├─ Enables WinRM                                  │
│        ├─ Stores admin password in Key Vault (optional)  │
│        └─ STOPS (no DC promotion)                        │
│                                                          │
│  2. ANSIBLE (DC Promotion):                              │
│     ├─ You create Ansible Vault:                         │
│     │  ansible/group_vars/vault.yml (encrypted):         │
│     │    vault_admin_password: "LocalAdmin123!"          │
│     │    vault_domain_admin_password: "DomainAdmin456!"  │
│     │    vault_dsrm_password: "DSRM789!"                 │
│     │                                                     │
│     ├─ Ansible reads from Ansible Vault                  │
│     │                                                     │
│     ├─ Connects via WinRM: azureadmin:LocalAdmin123!     │
│     │                                                     │
│     └─ Runs playbook:                                    │
│        ├─ Installs AD DS role                            │
│        ├─ Creates PSCredential with domain admin         │
│        └─ Install-ADDSDomainController                   │
│                                                          │
│  RESULT: ✅ DC promoted by Ansible                       │
│  TERRAFORM USED: ✅ YES (VMs only, no DC promotion)      │
│  ANSIBLE USED: ✅ YES (DC promotion)                     │
│                                                          │
└─────────────────────────────────────────────────────────┘

Credentials Stored: 
  - Terraform: Environment variables (TF_VAR_*) → Optional Key Vault
  - Ansible: Ansible Vault (encrypted file)

Credentials Used By:
  - Terraform: For VM creation (admin password)
  - Ansible: For DC promotion (admin + domain admin + DSRM)

NOTE: Credentials are stored in TWO separate places!
```

**Commands:**

```bash
# Step 1: Terraform creates VMs (no DC promotion)
export TF_VAR_admin_password="LocalAdmin123!"
cd terraform/environments/production

# IMPORTANT: Set this to skip DC promotion
cat > terraform.tfvars <<EOF
promote_to_dc = false
admin_username = "azureadmin"
# ... other settings
EOF

terraform apply
# Creates VMs, enables WinRM, STOPS (no DC promotion)

# Step 2: Create Ansible Vault
cd ../../ansible
cp group_vars/vault.yml.example group_vars/vault.yml

# Edit vault file
vi group_vars/vault.yml
# vault_admin_password: "LocalAdmin123!"  (same as Terraform!)
# vault_domain_admin_password: "DomainAdmin456!"
# vault_dsrm_password: "DSRM789!"

# Encrypt
ansible-vault encrypt group_vars/vault.yml

# Step 3: Run Ansible playbook
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --ask-vault-pass
# Ansible promotes DC using credentials from Ansible Vault
```

**Where Credentials Come From:**
- **Terraform phase**: Environment variables (TF_VAR_admin_password)
- **Ansible phase**: Ansible Vault (vault.yml encrypted file)
- **Azure Key Vault**: Optional (Terraform can store, but Ansible reads from Ansible Vault)

**⚠️ IMPORTANT**: You need to provide admin password TWICE:
1. Once to Terraform (TF_VAR_admin_password)
2. Once in Ansible Vault (vault_admin_password)

They should match!

---

### **Option 3: Terraform (All) + Ansible (Additional Config)**

**What happens:** Terraform does VM + DC promotion, Ansible adds extras

**Credential Storage:** Azure Key Vault (Terraform) + Ansible Vault (for AD object creation)

**Credential Flow:**

```
┌─────────────────────────────────────────────────────────┐
│  OPTION 3: TERRAFORM (ALL) + ANSIBLE (EXTRAS)            │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. TERRAFORM (VM + DC Promotion):                       │
│     ├─ You provide credentials:                          │
│     │  export TF_VAR_admin_password="LocalAdmin123!"     │
│     │  export TF_VAR_domain_admin_password="DomainAdmin456!" │
│     │  export TF_VAR_dsrm_password="DSRM789!"            │
│     │                                                     │
│     ├─ Set promote_to_dc = true (do DC promotion)        │
│     │                                                     │
│     └─ Terraform:                                        │
│        ├─ Stores credentials in Azure Key Vault         │
│        ├─ Creates VMs: azureadmin:LocalAdmin123!         │
│        ├─ Enables WinRM                                  │
│        └─ Promotes to DC ✅ (using Key Vault creds)      │
│                                                          │
│  2. ANSIBLE (Additional Config - AFTER DC exists):       │
│     ├─ DC is already promoted by Terraform               │
│     │                                                     │
│     ├─ You create Ansible Vault (optional):              │
│     │  ansible/group_vars/vault.yml (encrypted):         │
│     │    vault_domain_admin_password: "DomainAdmin456!"  │
│     │    (for creating OUs, users, groups)               │
│     │                                                     │
│     ├─ OR Ansible reads from Azure Key Vault:            │
│     │  azure_rm_keyvaultsecret_info module               │
│     │                                                     │
│     └─ Runs playbook:                                    │
│        ├─ Creates OUs (Servers, Users, Groups)           │
│        ├─ Configures password policies                   │
│        ├─ Enables AD Recycle Bin                         │
│        ├─ Security hardening                             │
│        └─ Backup scripts                                 │
│                                                          │
│  RESULT: ✅ DC promoted by Terraform                     │
│          ✅ Advanced config by Ansible                    │
│                                                          │
└─────────────────────────────────────────────────────────┘

Credentials Stored:
  - Terraform: Azure Key Vault (all passwords)
  - Ansible: Can read from Azure Key Vault OR use Ansible Vault

Credentials Used By:
  - Terraform: For VM creation + DC promotion (from Key Vault)
  - Ansible: For AD object creation (from Key Vault or Ansible Vault)

BEST: Ansible reads from same Azure Key Vault Terraform created!
```

**Commands:**

```bash
# Step 1: Terraform does everything (VM + DC promotion)
export TF_VAR_admin_password="LocalAdmin123!"
export TF_VAR_domain_admin_password="DomainAdmin456!"
export TF_VAR_dsrm_password="DSRM789!"

cd terraform/environments/production

# IMPORTANT: Set this to enable DC promotion
cat > terraform.tfvars <<EOF
promote_to_dc = true  # ← Terraform does DC promotion!
admin_username = "azureadmin"
# ... other settings
EOF

terraform apply
# Creates VMs, promotes to DC, stores creds in Key Vault
# DC is now ready! ✅

# Step 2: Ansible adds advanced config (OPTIONAL)
cd ../../ansible

# Option A: Use Azure Key Vault (recommended)
export AZURE_KEY_VAULT_NAME="ad-prod-kv-xyz"

ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  --tags="security,post-install"

# Playbook reads from Azure Key Vault:
- name: Get domain admin password
  azure.azcollection.azure_rm_keyvaultsecret_info:
    vault_uri: "https://{{ azure_key_vault_name }}.vault.azure.net"
    secret_name: "domain-admin-password"

# Option B: Use Ansible Vault
# Create vault.yml, encrypt it, run with --ask-vault-pass
```

**Where Credentials Come From:**
- **Terraform phase**: Environment variables → stored in Azure Key Vault
- **Ansible phase**: Reads from Azure Key Vault (preferred) OR Ansible Vault
- **Best Practice**: Ansible reuses credentials from Azure Key Vault (single source of truth!)

---

## 🎯 **SUMMARY TABLE: Where Credentials Are**

| Option | Terraform Uses | Ansible Uses | DC Promoted By | Best Storage Choice |
|--------|---------------|--------------|----------------|---------------------|
| **Option 1: Terraform Only** | Azure Key Vault | N/A (not used) | Terraform | Azure Key Vault |
| **Option 2: TF + Ansible Alt** | Env vars (or Key Vault for VMs) | Ansible Vault | Ansible | Ansible Vault |
| **Option 3: TF + Ansible Both** | Azure Key Vault | Azure Key Vault (or Ansible Vault) | Terraform | Azure Key Vault (shared!) |

---

## 🔍 **Key Insights:**

### **1. You Don't Store Credentials Everywhere!**

```
❌ WRONG:
   Store in Azure Key Vault AND Ansible Vault AND env vars

✅ RIGHT:
   Choose ONE primary storage:
   - Azure Key Vault (if using Terraform for DC promotion)
   - Ansible Vault (if using Ansible for DC promotion)
   - Env vars (testing only)
```

---

### **2. Initial vs Runtime Storage:**

| Phase | What Happens | Example |
|-------|--------------|---------|
| **Initial Load** | You provide creds via env vars | `export TF_VAR_admin_password="..."` |
| **Storage** | Tool stores in persistent storage | Terraform → Azure Key Vault<br>You → Ansible Vault |
| **Runtime** | Tool reads from storage | Terraform reads from Key Vault<br>Ansible reads from Ansible Vault |

**After initial setup, env vars are no longer needed!**

---

### **3. For Each Option:**

**Option 1 (Terraform Only):**
```
Initial: export TF_VAR_* (3 passwords)
Storage: Azure Key Vault (created by Terraform)
Runtime: Terraform reads from Key Vault
Result: No Ansible Vault needed
```

**Option 2 (TF + Ansible Alt):**
```
Initial: 
  - export TF_VAR_admin_password (for Terraform)
  - Create ansible/group_vars/vault.yml (for Ansible)
Storage: 
  - Terraform: optional Key Vault (for VMs)
  - Ansible: Ansible Vault (mandatory for DC promotion)
Runtime:
  - Terraform reads from env vars (or Key Vault)
  - Ansible reads from Ansible Vault
Result: Credentials in TWO places (TF and Ansible separate)
```

**Option 3 (TF All + Ansible Extras):**
```
Initial: export TF_VAR_* (3 passwords)
Storage: Azure Key Vault (created by Terraform)
Runtime:
  - Terraform reads from Key Vault (for DC promotion)
  - Ansible ALSO reads from same Key Vault (for extras)
Result: Single source of truth! ✅
```

---

## ✅ **Recommended Approaches:**

### **For Production:**

**Use Option 3 with Azure Key Vault:**

```bash
# 1. Initial setup (one-time)
export TF_VAR_admin_password="LocalAdmin123!"
export TF_VAR_domain_admin_password="DomainAdmin456!"
export TF_VAR_dsrm_password="DSRM789!"

# 2. Terraform stores in Key Vault and promotes DC
terraform apply

# 3. Ansible reads from SAME Key Vault for extras
export AZURE_KEY_VAULT_NAME="ad-prod-kv-xyz"
ansible-playbook playbooks/site.yml --tags="post-install"
```

**Benefits:**
- ✅ Single source of truth (Azure Key Vault)
- ✅ Both tools use same credentials
- ✅ Automatic encryption, audit logs
- ✅ Supports rotation

---

### **For Testing/POC:**

**Use Option 1 with Environment Variables:**

```bash
# Just export and run Terraform
export TF_VAR_admin_password="LocalAdmin123!"
export TF_VAR_domain_admin_password="DomainAdmin456!"
export TF_VAR_dsrm_password="DSRM789!"

terraform apply
# Done! No Key Vault setup needed
```

**Benefits:**
- ✅ Fastest to get started
- ✅ No cloud costs
- ✅ Simple for labs

---

## 🎯 **Final Answer to Your Questions:**

### **Q1: Are credentials stored in all those places?**

**NO!** You choose ONE:
- **Azure Key Vault** (production)
- **Ansible Vault** (Ansible-first approach)
- **Environment Variables** (testing only)

You don't use all three simultaneously!

---

### **Q2: For 3 DC promotion options, where do credentials come from?**

| Option | Credentials Come From |
|--------|-----------------------|
| **1. Terraform Only** | Azure Key Vault (created by Terraform from env vars) |
| **2. TF + Ansible Alt** | Terraform: env vars<br>Ansible: Ansible Vault<br>(Two separate sources) |
| **3. TF All + Ansible Extras** | Azure Key Vault for both!<br>(Single source of truth) |

---

**Option 3 is the cleanest: One Key Vault, used by both Terraform and Ansible!** ✅

---

*Document Date: January 20, 2026*
