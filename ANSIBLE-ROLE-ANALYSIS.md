# What Ansible Does in IaaC-v2-main

## 🎯 Key Finding: Ansible is **OPTIONAL** in your friend's project!

**Core DC Promotion** is done by **Terraform** using `azurerm_virtual_machine_run_command` (same approach as autodcbuild).

Ansible is provided as an **alternative/additional** configuration management tool for more complex scenarios.

---

## ⚠️ IMPORTANT: Terraform OR Ansible for DC Promotion (Not Both!)

**For DC promotion, you choose ONE method:**

| Method | How | When |
|--------|-----|------|
| **Terraform Only** | Set `promote_to_dc = true` | Default - 90% of deployments |
| **Ansible Instead** | Set `promote_to_dc = false`, run playbook | Alternative approach |

**For additional config (OUs, security), Ansible is used AFTER DC exists.**

---

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

### 🔄 **Ansible Does (Optional - Choose Your Path):**

**⚠️ IMPORTANT**: For DC promotion tasks, you choose **EITHER** Terraform **OR** Ansible, not both!

| Task | File | Usage Option |
|------|------|--------------|
| **DC PROMOTION TASKS** (Choose ONE method) | | |
| Install AD DS Features | `playbooks/site.yml` | **Instead of** Terraform (set `promote_to_dc=false`) |
| Join Existing Domain | `roles/domain-controller/tasks/join-domain.yml` | **Instead of** Terraform (set `promote_to_dc=false`) |
| Promote to DC | `roles/domain-controller/tasks/join-domain.yml` lines 63-98 | **Instead of** Terraform (set `promote_to_dc=false`) |
| **ADDITIONAL CONFIG TASKS** (After DC exists) | | |
| Security Hardening | `roles/security-hardening/` | **In addition to** Terraform (optional) |
| Create OUs | `roles/domain-controller/tasks/post-install.yml` lines 22-44 | **In addition to** Terraform (optional) |
| Password Policies | `roles/domain-controller/tasks/post-install.yml` lines 46-64 | **In addition to** Terraform (optional) |
| AD Recycle Bin | `roles/domain-controller/tasks/post-install.yml` lines 5-20 | **In addition to** Terraform (optional) |
| Audit Configuration | `roles/security-hardening/tasks/audit.yml` | **In addition to** Terraform (optional) |
| Certificate Setup | `roles/security-hardening/tasks/certificates.yml` | **In addition to** Terraform (optional) |
| Windows Security | `roles/security-hardening/tasks/windows-security.yml` | **In addition to** Terraform (optional) |

**Result**: Ansible can be used **instead of** Terraform for DC promotion, **OR** for advanced config **after** Terraform!

---

## 🤔 Why Include Ansible?

Your friend included Ansible for **two distinct purposes**:

### **Use Case 1: Alternative to Terraform for DC Promotion**
Some teams prefer Ansible over Terraform for:
- Configuration management consistency
- Existing Ansible expertise
- Better PowerShell/WinRM integration
- Ability to run playbooks separately for updates

**In this case**: Set `promote_to_dc = false` and use Ansible **instead of** Terraform

---

### **Use Case 2: Post-Deployment Configuration (Main Purpose)**
Things that are hard/impossible to do in Terraform:
- Creating OUs, users, groups
- Configuring password policies
- Enabling AD Recycle Bin
- Windows security hardening
- Audit policy configuration
- Certificate enrollment
- Backup script creation

**In this case**: Use Terraform for DC promotion, then Ansible **in addition** for enterprise features

---

### **Use Case 3: Complex Scenarios**
Advanced AD configurations:
- Multi-domain forests
- Trust relationships
- Custom GPO configurations
- Application-specific AD setup
- Ongoing configuration management

---

## 📋 Three Deployment Options

### **Option 1: Terraform ONLY** (Default - Most Common)
```bash
cd terraform/environments/production
terraform init
terraform apply

# Configuration:
# promote_to_dc = true  (Terraform does DC promotion)

# Result: 
# - VMs created ✅
# - DCs promoted by Terraform ✅
# - Basic health checks ✅
# - Done! (~30 min)
```

**Uses**: `azurerm_virtual_machine_run_command` (same as autodcbuild!)  
**Ansible Used**: NO

---

### **Option 2: Terraform (Infra) + Ansible (DC Promotion)**
```bash
# Step 1: Deploy infrastructure only
cd terraform/environments/production
terraform init
terraform apply

# Configuration:
# promote_to_dc = false  (Terraform skips DC promotion)

# Step 2: Use Ansible to promote DCs instead
cd ../../ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# Result:
# - VMs created by Terraform ✅
# - DCs promoted by Ansible ✅
# - Done! (~40 min)
```

**Uses**: Ansible for DC promotion **instead of** Terraform run commands  
**Ansible Used**: YES (for DC promotion)

---

### **Option 3: Terraform (All) + Ansible (Additional Config)**
```bash
# Step 1: Deploy infrastructure + promote DCs
cd terraform/environments/production
terraform init
terraform apply

# Configuration:
# promote_to_dc = true  (Terraform does DC promotion)

# Step 2: Run Ansible for advanced enterprise features
cd ../../ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags="security,post-install"

# Result:
# - VMs created by Terraform ✅
# - DCs promoted by Terraform ✅
# - PLUS security hardening by Ansible ✅
# - PLUS AD objects (OUs, users) by Ansible ✅
# - PLUS advanced config by Ansible ✅
# - Done! (~50 min)
```

**Uses**: Terraform for DC promotion, Ansible for additional enterprise features  
**Ansible Used**: YES (for advanced config only)

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

## 📊 Comparison Table (Updated)

| Task | autodcbuild | IaaC-v2 Option 1<br>(Terraform Only) | IaaC-v2 Option 2<br>(Terraform+Ansible) | IaaC-v2 Option 3<br>(Both) |
|------|-------------|---------------------------|---------------------|---------------------|
| **Core Method** | GitHub Actions + az CLI | Terraform + run-command | Terraform (infra)<br>Ansible (DC) | Terraform (all)<br>+ Ansible (extras) |
| **VM Creation** | ✅ GitHub Actions | ✅ Terraform | ✅ Terraform | ✅ Terraform |
| **DC Promotion** | ✅ az run-command | ✅ Terraform run-command | ✅ Ansible playbook | ✅ Terraform run-command |
| **Basic Health** | ✅ | ✅ | ✅ | ✅ |
| **DNS Forwarders** | ✅ 2 zones | ✅ 2 zones | ✅ 2 zones | ✅ 4 zones |
| **Create OUs** | ❌ | ❌ | ❌ | ✅ Ansible |
| **Password Policy** | ❌ | ❌ | ❌ | ✅ Ansible |
| **Security Hardening** | ❌ | ❌ | ❌ | ✅ Ansible |
| **AD Recycle Bin** | ❌ | ❌ | ❌ | ✅ Ansible |
| **Backup Scripts** | ❌ | ❌ | ❌ | ✅ Ansible |
| **Time** | ~7 min | ~30 min | ~40 min | ~50 min |
| **Ansible for DC?** | No | No | **Yes (instead)** | No |
| **Ansible for Config?** | No | No | No | **Yes (additional)** |

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

### **Three Ways to Use IaaC-v2-main:**

```
Option 1 (Default - 90% of users):
  Terraform → Creates VMs + Promotes DC → Done! ✅
  Time: 30 min | Ansible: NOT used

Option 2 (Alternative method):
  Terraform → Creates VMs only
       ↓
  Ansible → Promotes DC → Done! ✅
  Time: 40 min | Ansible: Used INSTEAD of Terraform run-command

Option 3 (Comprehensive):
  Terraform → Creates VMs + Promotes DC ✅
       ↓
  Ansible → Adds enterprise features ✅✅
  Time: 50 min | Ansible: Used IN ADDITION to Terraform
```

### **Key Principle:**

**For DC Promotion**: Choose **ONE** method (Terraform OR Ansible)  
**For Additional Config**: Use Ansible **AFTER** DC is promoted

### **Compared to autodcbuild:**

```
autodcbuild:
  GitHub Actions → az vm run-command → DC ready in 7 min
  (Assumes existing infrastructure)

IaaC-v2-main Option 1:
  Terraform → azurerm run-command → DC ready in 30 min
  (Creates full infrastructure + DC)
  
IaaC-v2-main Option 2:
  Terraform + Ansible → DC ready in 40 min
  (Creates infra via Terraform, DC via Ansible)

IaaC-v2-main Option 3:
  Terraform + Ansible → Enterprise DC in 50 min
  (Terraform for DC + Ansible for advanced features)
```

---

## 🏆 Verdict

### **Ansible's Role in IaaC-v2-main:**

1. **For DC Promotion**: **OPTIONAL** - You can use Ansible **instead of** Terraform run commands
   - Set `promote_to_dc = false` to use this approach
   - Most people (90%) don't use this - they let Terraform do it

2. **For Advanced Config**: **OPTIONAL** - You can use Ansible **in addition to** Terraform
   - OUs, users, groups, policies, security hardening
   - This is the main reason Ansible is included

### **Clear Answer to "Do We Use Both?"**

**For DC Promotion**: **NO** - Choose ONE method (Terraform OR Ansible)  
**For Additional Config**: **YES** - Ansible adds features after Terraform completes

### **Bottom Line:**

| Project | Method | DC Promotion Time | Best For |
|---------|--------|-------------------|----------|
| **autodcbuild** | GitHub Actions + az CLI | **7 min** | Lab/Quick testing |
| **IaaC-v2 (Option 1)** | Terraform only | 30 min | Production infrastructure |
| **IaaC-v2 (Option 2)** | Terraform + Ansible (alt) | 40 min | Teams who prefer Ansible |
| **IaaC-v2 (Option 3)** | Terraform + Ansible (both) | 50 min | Enterprise with all features |

**Your autodcbuild project is fastest** because it assumes existing infrastructure!  
**IaaC-v2-main is more comprehensive** because it creates everything from scratch! 🚀

---

*Analysis Date: January 20, 2026*
