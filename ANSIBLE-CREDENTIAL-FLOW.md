# Ansible Credential Flow in IaaC-v2-main

## 🔐 How Ansible Uses WinRM Credentials for DC Promotion

Complete guide to understanding how credentials are created, stored, passed, and used when Ansible runs playbooks against Windows servers.

---

## 📊 **High-Level Credential Flow**

```
┌─────────────────────────────────────────────────────────────────┐
│                   CREDENTIAL SOURCES                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Azure Key Vault          2. Ansible Vault       3. Env Vars │
│     (Terraform managed)          (ansible-vault)       (export)  │
│            ↓                          ↓                    ↓     │
│            └──────────────────────────┴────────────────────┘     │
│                                 ↓                                │
│                    ┌────────────────────────┐                    │
│                    │  Ansible Playbook      │                    │
│                    │  Execution             │                    │
│                    └────────────────────────┘                    │
│                                 ↓                                │
│                    ┌────────────────────────┐                    │
│                    │  WinRM Connection      │                    │
│                    │  (NTLM/Kerberos)       │                    │
│                    └────────────────────────┘                    │
│                                 ↓                                │
│                    ┌────────────────────────┐                    │
│                    │  Windows Server        │                    │
│                    │  (Execute PowerShell)  │                    │
│                    └────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔑 **1. Credential Creation & Storage**

### **A. Terraform Creates Credentials**

When Terraform creates VMs, it generates and stores credentials:

```hcl
# terraform/environments/production/main.tf
resource "azurerm_windows_virtual_machine" "dc" {
  name     = "DC01"
  admin_username = var.admin_username  # e.g., "azureadmin"
  admin_password = var.admin_password  # From TF_VAR_admin_password
  
  # Password is also stored in Key Vault
  depends_on = [azurerm_key_vault_secret.admin_password]
}
```

**Credential Types Created:**

| Credential | Purpose | Created By | Used For |
|------------|---------|------------|----------|
| **Local Admin** | VM login | Terraform | Initial WinRM connection |
| **Domain Admin** | AD operations | Provided by user | Domain join & DC promotion |
| **DSRM Password** | Recovery mode | Provided by user | DC disaster recovery |

---

### **B. Azure Key Vault Storage**

```hcl
# terraform/modules/security/main.tf
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "domain_admin_password" {
  name         = "domain-admin-password"
  value        = var.domain_admin_password
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "dsrm_password" {
  name         = "dsrm-password"
  value        = var.dsrm_password
  key_vault_id = azurerm_key_vault.main.id
}
```

**Benefits:**
- ✅ Centralized secret management
- ✅ Audit logs for secret access
- ✅ Role-based access control
- ✅ Automatic rotation support
- ✅ Encrypted at rest

---

### **C. Ansible Vault Storage (Alternative)**

```yaml
# ansible/group_vars/vault.yml (encrypted)
vault_admin_password: "SecurePassword123!"
vault_domain_admin_password: "DomainAdmin456!"
vault_dsrm_password: "DSRMPassword789!"
```

**How to Create:**

```bash
# Create and encrypt vault file
cd ansible
cp group_vars/vault.yml.example group_vars/vault.yml

# Edit with actual passwords
vi group_vars/vault.yml

# Encrypt the file
ansible-vault encrypt group_vars/vault.yml
# Enter vault password: ********

# Now vault.yml is encrypted
cat group_vars/vault.yml
# Output: $ANSIBLE_VAULT;1.1;AES256...
```

**Vault Password Options:**

```bash
# Option 1: Interactive prompt
ansible-playbook playbooks/site.yml --ask-vault-pass

# Option 2: Password file
echo "my_vault_password" > .vault_pass
chmod 600 .vault_pass
ansible-playbook playbooks/site.yml --vault-password-file=.vault_pass

# Option 3: Configure in ansible.cfg
# ansible/ansible.cfg
[defaults]
vault_password_file = .vault_pass
```

---

### **D. Environment Variables (Quick/Testing)**

```bash
# Set credentials as environment variables
export ADMIN_PASSWORD="SecurePassword123!"
export DOMAIN_ADMIN_PASSWORD="DomainAdmin456!"
export DSRM_PASSWORD="DSRMPassword789!"
export AZURE_KEY_VAULT_NAME="ad-prod-kv-xyz"

# Ansible can access these
ansible-playbook playbooks/site.yml
```

---

## 🔌 **2. WinRM Connection Setup**

### **A. Ansible Inventory Configuration**

```yaml
# ansible/inventory/existing_domain_hosts.yml
all:
  vars:
    # WinRM connection settings
    ansible_connection: winrm       # Use WinRM protocol
    ansible_port: 5985              # HTTP (5986 for HTTPS)
    ansible_winrm_transport: ntlm   # or 'kerberos' for domain auth
    ansible_winrm_server_cert_validation: ignore  # For self-signed certs
    
    # Initial connection (before domain join)
    ansible_user: azureadmin        # Local admin username
    ansible_password: "{{ vault_admin_password }}"  # From vault
    
  children:
    new_domain_controllers:
      hosts:
        new-dc01:
          ansible_host: 10.0.1.4    # IP address of the VM
```

**Connection Flow:**

```
Ansible Control Node (Linux/Mac)
    ↓ (WinRM over HTTP/HTTPS)
    ↓ (Port 5985 or 5986)
    ↓ (NTLM Authentication)
Windows Server (10.0.1.4)
    ↓ (Authenticates: azureadmin)
    ↓ (Executes PowerShell commands)
Domain Controller Operations
```

---

### **B. WinRM Configuration on Windows**

**Terraform ensures WinRM is enabled:**

```powershell
# Via Custom Script Extension during VM creation
# terraform/modules/compute/main.tf

resource "azurerm_virtual_machine_extension" "winrm" {
  name                 = "configure-winrm"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell.exe -ExecutionPolicy Unrestricted -Command \"Enable-PSRemoting -Force; Set-Item WSMan:\\localhost\\Service\\Auth\\Basic -Value $true; winrm set winrm/config/service '@{AllowUnencrypted=\"true\"}'\""
    }
  SETTINGS
}
```

**What This Does:**
1. **Enable-PSRemoting**: Turns on PowerShell remoting
2. **Set Basic Auth**: Allows username/password auth
3. **Allow Unencrypted**: For HTTP (port 5985)
4. **Firewall rules**: Automatically configured

---

## 🚀 **3. Credential Usage During Playbook Execution**

### **A. Initial Connection (Local Admin)**

```yaml
# ansible/roles/domain-controller/tasks/join-domain.yml

# Step 1: Connect via WinRM using local admin
- name: Check if already a Domain Controller
  ansible.windows.win_powershell:
    script: |
      # This runs as: azureadmin (local admin)
      Get-ADDomainController -ErrorAction Stop
  register: dc_status
```

**What Happens:**
1. Ansible reads `ansible_user` and `ansible_password` from inventory
2. Creates NTLM auth request to 10.0.1.4:5985
3. Windows validates: "azureadmin" + password
4. PowerShell session established
5. Script executes with local admin privileges

---

### **B. Domain Operations (Domain Admin)**

```yaml
# Step 2: Join domain and promote to DC
- name: Promote to Domain Controller
  ansible.windows.win_powershell:
    script: |
      # Create domain admin credential object
      $secPass = ConvertTo-SecureString '{{ domain_admin_password }}' -AsPlainText -Force
      $cred = New-Object System.Management.Automation.PSCredential(
        '{{ ad_domain_netbios_name }}\{{ domain_admin_username }}',
        $secPass
      )
      
      # Create DSRM password
      $dsrmPass = ConvertTo-SecureString '{{ dsrm_password }}' -AsPlainText -Force
      
      # Promote to DC (requires domain admin)
      Install-ADDSDomainController `
        -DomainName '{{ ad_domain_name }}' `
        -Credential $cred `
        -SafeModeAdministratorPassword $dsrmPass `
        -Force
  no_log: true  # Hide sensitive output
```

**Credential Flow:**

```
1. Ansible connects: azureadmin (local admin)
   ↓
2. Creates PSCredential: CORP\Administrator (domain admin)
   ↓
3. Install-ADDSDomainController uses domain admin credential
   ↓
4. AD validates domain admin against existing DC
   ↓
5. DC promotion succeeds
   ↓
6. Server reboots as Domain Controller
```

---

### **C. Multi-Phase Authentication**

```yaml
# Phase 1: Before Domain Join
ansible_user: azureadmin           # Local admin
ansible_password: "{{ vault_admin_password }}"

# Phase 2: After Domain Join (if needed)
ansible_user: "{{ ad_domain_netbios_name }}\\{{ domain_admin_username }}"
ansible_password: "{{ vault_domain_admin_password }}"
ansible_winrm_transport: kerberos  # Switch to Kerberos
```

---

## 📋 **4. Complete Credential Flow Example**

### **Scenario: Adding DC to Existing Domain**

```bash
# Step 1: User provides credentials
export TF_VAR_admin_password="LocalAdmin123!"
export TF_VAR_domain_admin_password="DomainAdmin456!"
export TF_VAR_dsrm_password="DSRM789!"

# Step 2: Terraform creates VM and stores creds
terraform apply
# - Creates VM with azureadmin:LocalAdmin123!
# - Stores passwords in Key Vault
# - Enables WinRM
# - Outputs ansible_inventory

# Step 3: Run Ansible playbook
cd ansible
ansible-playbook -i inventory/existing_domain_hosts.yml playbooks/site.yml

# Step 4: Ansible execution flow
# 
# 4a. Read credentials from vault
#     vault_admin_password: "LocalAdmin123!"
#     vault_domain_admin_password: "DomainAdmin456!"
#     vault_dsrm_password: "DSRM789!"
#
# 4b. Connect to VM via WinRM
#     Protocol: HTTP (5985)
#     Auth: NTLM
#     User: azureadmin
#     Pass: LocalAdmin123!
#
# 4c. Execute DC promotion script
#     Running as: azureadmin (local admin)
#     
#     Script creates PSCredential:
#       User: CORP\Administrator
#       Pass: DomainAdmin456!
#     
#     Install-ADDSDomainController with domain admin cred
#     
#     AD validates against existing DC:
#       - Checks CORP\Administrator credentials
#       - Grants permission to add new DC
#       - Replicates AD database
#       - Sets DSRM password: DSRM789!
#
# 4d. Server reboots as DC
#
# 4e. Post-promotion tasks
#     Connect again via WinRM (still azureadmin)
#     Or switch to domain admin if needed
```

---

## 🔒 **5. Security Best Practices**

### **A. Credential Hierarchy**

| Credential Type | Storage | Access | Rotation |
|-----------------|---------|--------|----------|
| **Local Admin** | Azure Key Vault | Terraform, Ansible | 90 days |
| **Domain Admin** | Azure Key Vault | Ansible only | 60 days |
| **DSRM Password** | Azure Key Vault | Backup/recovery | 180 days |
| **Ansible Vault Master** | Secure file (.vault_pass) | CI/CD system | Yearly |

---

### **B. Principle of Least Privilege**

```yaml
# DON'T: Use domain admin for everything
ansible_user: "CORP\\Administrator"
ansible_password: "{{ vault_domain_admin_password }}"

# DO: Use local admin for WinRM, elevate only when needed
ansible_user: "azureadmin"
ansible_password: "{{ vault_admin_password }}"

# Then in playbook, use domain admin only for DC promotion:
- name: Promote to DC
  ansible.windows.win_powershell:
    script: |
      $cred = New-Object PSCredential("CORP\\Administrator", $secPass)
      Install-ADDSDomainController -Credential $cred
```

---

### **C. Credential Transmission**

```yaml
# Ansible ensures credentials are NOT logged
- name: Promote to DC
  ansible.windows.win_powershell:
    script: |
      # Credentials in script
    no_log: true  # ← Prevents output from appearing in logs

# Also in ansible.cfg:
[defaults]
no_log = True
no_target_syslog = True
```

**Encryption in Transit:**
- WinRM over HTTPS (port 5986): Encrypted
- WinRM over HTTP (port 5985): **Unencrypted** ⚠️
  - Use only on trusted networks (VNet)
  - Enable HTTPS for production

---

### **D. Azure Key Vault Integration**

```yaml
# Ansible can fetch secrets directly from Azure Key Vault
- name: Get admin password from Key Vault
  azure.azcollection.azure_rm_keyvaultsecret_info:
    vault_uri: "https://{{ azure_key_vault_name }}.vault.azure.net"
    secret_name: "admin-password"
  register: kv_admin_password

- name: Set admin password variable
  set_fact:
    admin_password: "{{ kv_admin_password.secrets[0].secret }}"
  no_log: true
```

**Requirements:**
```bash
# Install Azure collection
ansible-galaxy collection install azure.azcollection

# Authenticate to Azure
az login
export AZURE_SUBSCRIPTION_ID="your-sub-id"
```

---

## 🎯 **6. Complete Playbook Example**

```yaml
# playbooks/promote-dc.yml
---
- name: Promote Server to Domain Controller
  hosts: new_domain_controllers
  gather_facts: true
  
  vars:
    # Credentials from vault
    admin_password: "{{ vault_admin_password }}"
    domain_admin_password: "{{ vault_domain_admin_password }}"
    dsrm_password: "{{ vault_dsrm_password }}"
  
  tasks:
    - name: Display connection info
      ansible.builtin.debug:
        msg: |
          Connecting to: {{ ansible_host }}
          User: {{ ansible_user }}
          Transport: {{ ansible_winrm_transport }}
          Port: {{ ansible_port }}
      no_log: false  # This is OK to log (no passwords)
    
    - name: Test WinRM connection
      ansible.windows.win_ping:
      # Uses: ansible_user + ansible_password from inventory
    
    - name: Configure DNS to point to existing DC
      ansible.windows.win_dns_client:
        adapter_names: '*'
        dns_servers:
          - "{{ existing_dc_ip }}"
    
    - name: Install AD DS role
      ansible.windows.win_feature:
        name: AD-Domain-Services
        include_management_tools: true
        state: present
      register: adds_install
    
    - name: Reboot if required
      ansible.windows.win_reboot:
        reboot_timeout: 600
      when: adds_install.reboot_required
    
    - name: Promote to Domain Controller
      ansible.windows.win_powershell:
        script: |
          Import-Module ADDSDeployment
          
          # Create domain admin credential
          $domainAdminPass = ConvertTo-SecureString "{{ domain_admin_password }}" -AsPlainText -Force
          $domainCred = New-Object PSCredential(
            "{{ ad_domain_netbios_name }}\\{{ domain_admin_username }}",
            $domainAdminPass
          )
          
          # Create DSRM password
          $dsrmPass = ConvertTo-SecureString "{{ dsrm_password }}" -AsPlainText -Force
          
          # Promote to DC
          Install-ADDSDomainController `
            -DomainName "{{ ad_domain_name }}" `
            -Credential $domainCred `
            -SafeModeAdministratorPassword $dsrmPass `
            -DatabasePath "C:\\Windows\\NTDS" `
            -LogPath "C:\\Windows\\NTDS" `
            -SysvolPath "C:\\Windows\\SYSVOL" `
            -InstallDns:$true `
            -NoRebootOnCompletion:$false `
            -Force:$true
      no_log: true  # Hide credentials
      register: dc_promotion
    
    - name: Wait for DC to come back online
      ansible.windows.win_ping:
      retries: 30
      delay: 60
      until: result is success
      register: result
```

**Run the playbook:**

```bash
# With vault password
ansible-playbook playbooks/promote-dc.yml --ask-vault-pass

# Or with vault password file
ansible-playbook playbooks/promote-dc.yml --vault-password-file=.vault_pass

# Verbose output (debugging)
ansible-playbook playbooks/promote-dc.yml -vvv
```

---

## 🔍 **7. Troubleshooting Credentials**

### **A. Test WinRM Connection**

```bash
# Test from Ansible control node
ansible new-dc01 -m ansible.windows.win_ping -i inventory/existing_domain_hosts.yml

# If it fails, check:
# 1. VM is running
# 2. Network connectivity (port 5985/5986 open)
# 3. Credentials are correct
# 4. WinRM is enabled on Windows server
```

---

### **B. Test PowerShell Remoting Manually**

```bash
# From Mac/Linux with PowerShell Core
pwsh

# Create PSCredential
$password = ConvertTo-SecureString "LocalAdmin123!" -AsPlainText -Force
$cred = New-Object PSCredential("azureadmin", $password)

# Test connection
$session = New-PSSession -ComputerName 10.0.1.4 -Port 5985 -Credential $cred -Authentication Negotiate -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)

# Run command
Invoke-Command -Session $session -ScriptBlock { Get-ComputerInfo }

# Clean up
Remove-PSSession $session
```

---

### **C. Verify Azure Key Vault Access**

```bash
# Check if secrets exist
az keyvault secret list --vault-name ad-prod-kv-xyz

# Get specific secret (for testing)
az keyvault secret show --vault-name ad-prod-kv-xyz --name admin-password --query value -o tsv

# Verify access permissions
az keyvault show --name ad-prod-kv-xyz --query properties.accessPolicies
```

---

### **D. Check Ansible Vault**

```bash
# Decrypt and view vault contents (for debugging)
ansible-vault decrypt group_vars/vault.yml
cat group_vars/vault.yml
ansible-vault encrypt group_vars/vault.yml  # Re-encrypt!

# Or view without decrypting
ansible-vault view group_vars/vault.yml
```

---

## 📝 **Summary**

### **Credential Flow Quick Reference:**

```
1. CREATION
   - Terraform creates VMs with local admin
   - Stores passwords in Azure Key Vault
   - User provides domain admin & DSRM passwords

2. STORAGE
   - Azure Key Vault (recommended)
   - Ansible Vault (encrypted file)
   - Environment variables (testing only)

3. CONNECTION
   - Ansible connects via WinRM (port 5985/5986)
   - Uses local admin credentials (ansible_user/password)
   - NTLM or Kerberos authentication

4. EXECUTION
   - PowerShell runs as local admin
   - Creates PSCredential for domain admin
   - Passes domain admin to Install-ADDSDomainController
   - Sets DSRM password for recovery

5. SECURITY
   - no_log: true to hide credentials in output
   - HTTPS for WinRM in production
   - Least privilege (local admin → domain admin only when needed)
   - Regular password rotation
```

---

**Key Takeaway**: Ansible uses **two sets of credentials** - local admin for WinRM connection, and domain admin for DC promotion operations. They're kept separate and only domain admin is used for privileged AD operations.

---

*Document Date: January 20, 2026*
