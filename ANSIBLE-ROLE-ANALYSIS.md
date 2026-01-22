# What Ansible Does in IaaC-v2-main

## 🎯 Key Finding: Ansible is **OPTIONAL** in your friend's project!

**Core DC Promotion** is done by **Terraform** using `azurerm_virtual_machine_run_command` (same approach as autodcbuild).

Ansible is provided as an **alternative/additional** configuration management tool for more complex scenarios.

---

## 🏗️ Actual Architecture in IaaC-v2-main

```
Terraform (Primary)
    ├─ Creates Infrastructure (VNet, VMs, NSGs, Bastion, etc.)
    ├─ Promotes DCs via azurerm_virtual_machine_run_command
    │  ├─ Installs AD DS role
    │  ├─ Configures DNS
    │  ├─ Promotes to DC (Install-ADDSDomainController)
    │  └─ Handles reboot
    │
    └─ Outputs Ansible inventory (optional)

Ansible (Optional/Alternative)
    └─ Used for advanced post-configuration
       ├─ Security hardening
       ├─ AD object creation (OUs, Users, Groups)
       ├─ Additional configuration
       └─ Complex multi-DC scenarios
```

---

## 📊 What Terraform Does vs What Ansible Does

### ✅ **Terraform Does (Core - ALWAYS):**

| Task | Method | File |
|------|--------|------|
| Create VMs | `azurerm_windows_virtual_machine` | `modules/compute/main.tf` |
| Configure Networking | `azurerm_virtual_network`, NSGs | `modules/networking/main.tf` |
| VNet Peering | `azurerm_virtual_network_peering` | `vnet-peering.tf` |
| Install AD DS | `azurerm_virtual_machine_run_command` | `domain-join.tf` lines 25-120 |
| Configure DNS | PowerShell in run command | `domain-join.tf` lines 54-57 |
| Promote to DC | PowerShell in run command | `domain-join.tf` lines 87-96 |
| Bastion/Key Vault | Azure resources | Various modules |

**Result**: Terraform **ALONE** can deploy a working DC!

### 🔄 **Ansible Does (Optional - WHEN USED):**

| Task | File | When Used |
|------|------|-----------|
| Install AD DS Features | `playbooks/site.yml` | Alternative to Terraform |
| Join Existing Domain | `roles/domain-controller/tasks/join-domain.yml` | Alternative to Terraform |
| Promote to DC | `roles/domain-controller/tasks/join-domain.yml` lines 63-98 | Alternative to Terraform |
| Security Hardening | `roles/security-hardening/` | Post-deployment |
| Create OUs | `roles/domain-controller/tasks/post-install.yml` lines 22-44 | Post-deployment |
| Password Policies | `roles/domain-controller/tasks/post-install.yml` lines 46-64 | Post-deployment |
| AD Recycle Bin | `roles/domain-controller/tasks/post-install.yml` lines 5-20 | Post-deployment |
| Audit Configuration | `roles/security-hardening/tasks/audit.yml` | Post-deployment |
| Certificate Setup | `roles/security-hardening/tasks/certificates.yml` | Post-deployment |
| Windows Security | `roles/security-hardening/tasks/windows-security.yml` | Post-deployment |

**Result**: Ansible is for **advanced configuration AFTER** Terraform deploys the DC!

---

## 🤔 Why Include Ansible?

Your friend included Ansible for:

### 1. **Post-Deployment Configuration**
Things that are hard/impossible to do in Terraform:
- Creating OUs, users, groups
- Configuring password policies
- Enabling AD Recycle Bin
- Windows security hardening
- Audit policy configuration

### 2. **Flexibility**
- Some teams prefer Ansible for configuration management
- Can run Ansible playbooks separately for updates
- Alternative to Terraform for DC promotion

### 3. **Complex Scenarios**
- Multi-domain forests
- Trust relationships
- Custom GPO configurations
- Application-specific AD setup

---

## 📋 Two Deployment Paths

### **Path A: Terraform Only** (Simpler, like autodcbuild)
```bash
cd terraform/environments/production
terraform init
terraform apply

# Result: 
# - VMs created ✅
# - DCs promoted ✅
# - Basic health checks ✅
# - Done! (~30 min)
```

**Uses**: `azurerm_virtual_machine_run_command` (same as autodcbuild!)

### **Path B: Terraform + Ansible** (Comprehensive)
```bash
# Step 1: Deploy infrastructure
cd terraform/environments/production
terraform init
terraform apply

# Step 2: Run Ansible for advanced config
cd ../../ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Result:
# - Everything from Path A ✅
# - PLUS security hardening ✅
# - PLUS AD objects (OUs, users) ✅
# - PLUS advanced config ✅
# - Done! (~50 min)
```

---

## 🔍 Detailed: What Ansible Adds

### **Common Role** (`roles/common/`)
- Timezone configuration
- Windows Update settings
- Performance tuning
- Monitoring agent setup

### **Domain Controller Role** (`roles/domain-controller/`)

#### When dc_role = 'join':
```yaml
1. Configure DNS → existing DC
2. Test connectivity (LDAP port 389, Kerberos 88)
3. Check if already a DC
4. Install AD DS feature
5. Promote to DC (Install-ADDSDomainController)
6. Wait for reboot
7. Verify DC status
8. Force replication sync
9. Update DNS to include new DC
```

#### Post-Install Tasks:
```yaml
1. Enable AD Recycle Bin (primary DC only)
2. Create standard OUs:
   - Servers
   - Workstations
   - Users
   - Groups
   - Service Accounts
   - Disabled Objects
3. Configure default domain password policy
4. Create DC health check script
5. Create AD backup script
```

### **Security Hardening Role** (`roles/security-hardening/`)

#### Audit Configuration:
- Windows Event log forwarding
- Security event auditing
- AD object access auditing

#### Windows Security:
- Firewall rules
- Local security policies
- Registry hardening
- Disable unnecessary services

#### AD Security:
- Fine-grained password policies
- Protected Users group
- Authentication policies
- Delegation restrictions

#### Certificates:
- LDAPS certificate configuration
- Auto-enrollment setup
- Certificate validation

---

## 📊 Comparison Table

| Task | autodcbuild | IaaC-v2 (Terraform Only) | IaaC-v2 (+ Ansible) |
|------|-------------|---------------------------|---------------------|
| **Core Method** | GitHub Actions + az CLI | Terraform + az run-command | Terraform + Ansible |
| **VM Creation** | ✅ | ✅ | ✅ |
| **DC Promotion** | ✅ | ✅ | ✅ |
| **Basic Health** | ✅ | ✅ | ✅ |
| **DNS Forwarders** | ✅ 2 zones | ✅ 2 zones | ✅ 4 zones |
| **Create OUs** | ❌ | ❌ | ✅ |
| **Password Policy** | ❌ | ❌ | ✅ |
| **Security Hardening** | ❌ | ❌ | ✅ |
| **AD Recycle Bin** | ❌ | ❌ | ✅ |
| **Backup Scripts** | ❌ | ❌ | ✅ |
| **Time** | ~7 min | ~30 min | ~50 min |

---

## 💡 Key Insights

### **1. Terraform Does the Heavy Lifting**
Even in IaaC-v2-main, **Terraform alone** can:
- Create VMs
- Promote to DC
- Configure basic health

This is **SAME** as autodcbuild (just wrapped in Terraform instead of GitHub Actions)!

### **2. Ansible is the "Nice-to-Have"**
Ansible adds **enterprise features**:
- OUs and AD structure
- Password policies
- Security hardening
- Audit configuration

### **3. Both Use Same Core Method**
```
autodcbuild:  GitHub Actions → az vm run-command → PowerShell
IaaC-v2-main: Terraform → azurerm_virtual_machine_run_command → PowerShell
```

**Same PowerShell cmdlet**: `Install-ADDSDomainController`!

---

## 🎯 When to Use Ansible

### ✅ **Use Ansible When:**
1. You need to **create AD objects** (OUs, Users, Groups)
2. You want **security hardening** automated
3. You need **complex password policies**
4. You want **audit configuration**
5. You're managing **multiple domains**
6. You need **ongoing configuration management**
7. Your team **already knows Ansible**

### ❌ **Skip Ansible When:**
1. You just need a **working DC** (Terraform is enough!)
2. You want **speed** (Ansible adds 20 minutes)
3. You'll **configure AD manually**
4. You're in a **lab environment**
5. You don't need **advanced features**

---

## 📝 Summary

### **In IaaC-v2-main:**

```
Terraform = Core DC Deployment (REQUIRED)
    ↓
    Creates VMs + Promotes to DC
    ↓
    Working Domain Controller! ✅

Ansible = Advanced Configuration (OPTIONAL)
    ↓
    OUs + Users + Security + Policies
    ↓
    Enterprise-Ready DC! ✅✅
```

### **Compared to autodcbuild:**

```
autodcbuild:
  GitHub Actions → az vm run-command → DC ready in 7 min

IaaC-v2-main (Terraform only):
  Terraform → azurerm run-command → DC ready in 30 min
  
IaaC-v2-main (Terraform + Ansible):
  Terraform → DC → Ansible → Enterprise DC in 50 min
```

---

## 🏆 Verdict

**Ansible in IaaC-v2-main is for**:
- Post-deployment configuration
- Advanced AD setup
- Security hardening
- Ongoing management

**It's NOT required for basic DC promotion!**

Your friend's project gives you **flexibility**:
- Use Terraform only for speed
- Add Ansible when you need advanced features

**Your autodcbuild project achieves the same core result (working DC) in 7 minutes vs IaaC-v2's 30 minutes (Terraform only) or 50 minutes (Terraform + Ansible)!** 🚀

---

*Analysis Date: January 20, 2026*
