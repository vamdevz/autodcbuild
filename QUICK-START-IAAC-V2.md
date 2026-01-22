# IaaC-v2 Quick Start for LinkedIn.local Lab

## 🚀 **TL;DR - Fast Setup**

**Estimated Time:** 30 minutes  
**Complexity:** Medium (Terraform + Ansible)

---

## ✅ **Prerequisites (One-Time Setup)**

```bash
# Install tools
brew install terraform ansible
ansible-galaxy collection install azure.azcollection community.windows

# Login to Azure
az login
az account set --subscription "your-subscription-id"

# Set credentials
export TF_VAR_domain_admin_password='Sarita123@@@'
export TF_VAR_dsrm_password='Sarita123@@@'
```

---

## 📋 **Quick Deployment Steps**

### **1. Copy Project**

```bash
cd "/Volumes/Vamdev Data/Downloads/Projects"
cp -r autodcbuild/IaaC-v2-main linkedin-dc-terraform
cd linkedin-dc-terraform
```

### **2. Configure Terraform**

```bash
cd terraform/environments/existing-vm-promotion
cp terraform.tfvars.example terraform.tfvars
```

**Edit `terraform.tfvars`:**

```hcl
existing_vm_resource_group = "VAMDEVTEST"
existing_vm_name           = "windows11VM"  # Or your VM name
domain_name                = "linkedin.local"
domain_admin_username      = "vamdev"
existing_dc_ip             = "10.100.10.4"
install_dns                = true
site_name                  = "Default-First-Site-Name"
```

### **3. Deploy**

```bash
# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply

# Wait 15-30 minutes for DC promotion
```

### **4. Verify**

```bash
# Check outputs
terraform output

# RDP to VM and verify:
# - Active Directory Users and Computers shows linkedin.local
# - Run: Get-ADReplicationPartnerMetadata -Target *
# - Run: nslookup linkedin.local
```

---

## 🔧 **Configuration Quick Reference**

### **Your Environment Values**

| Item | Value |
|------|-------|
| Domain | `linkedin.local` |
| NetBIOS | `LINKEDIN` |
| Existing DC | `DC01` @ `10.100.10.4` |
| Resource Group | `VAMDEVTEST` |
| Admin User | `vamdev` |
| Admin Password | `Sarita123@@@` |

### **Files to Modify**

```
terraform/environments/existing-vm-promotion/terraform.tfvars  ← Main config
ansible/group_vars/all.yml                                     ← Domain name
ansible/inventory/linkedin_lab_hosts.yml                       ← IPs (if using Ansible)
```

---

## 🐛 **Common Issues**

### **Issue: Terraform Init Fails**
```bash
rm -rf .terraform .terraform.lock.hcl
terraform init
```

### **Issue: Azure Auth Fails**
```bash
az logout && az login
az account set --subscription "your-sub-id"
```

### **Issue: VM Not Found**
```bash
# List your VMs
az vm list --resource-group VAMDEVTEST --output table

# Use the correct name in terraform.tfvars
```

### **Issue: DC Promotion Fails - DNS**
```bash
# Check existing DC is running
az vm show -g VAMDEVTEST -n DC01 --query "powerState"

# Test connectivity from target VM
az vm run-command invoke \
  -g VAMDEVTEST \
  -n windows11VM \
  --command-id RunPowerShellScript \
  --scripts "Test-NetConnection -ComputerName 10.100.10.4 -Port 389"
```

---

## 📊 **What Gets Deployed**

**Terraform Does:**
1. ✅ Installs AD DS role on your VM
2. ✅ Configures DNS to point to DC01
3. ✅ Promotes VM to DC in linkedin.local
4. ✅ Reboots VM
5. ✅ Verifies DC services

**Time:** ~20-30 minutes

---

## 🎯 **Next Steps**

**After successful deployment:**

1. **Verify Replication:**
   ```powershell
   Get-ADReplicationPartnerMetadata -Target * | FT Server,LastReplicationSuccess
   ```

2. **Check DNS:**
   ```powershell
   nslookup linkedin.local
   nslookup DC01.linkedin.local
   ```

3. **Add OUs/Users (Optional):**
   ```bash
   cd ../../../ansible
   ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags="post-install"
   ```

---

## 💡 **Pro Tips**

1. **Use Terraform Plan First:** Always run `terraform plan` before `apply`
2. **Check VM State:** Ensure target VM is running before promotion
3. **Backup First:** Create VM snapshot before DC promotion
4. **Monitor Logs:** Watch Azure portal for VM activity
5. **Keep Credentials Safe:** Use environment variables, not commit to git

---

## 🎉 **Success Indicators**

After deployment, you should see:

✅ Terraform shows "Apply complete!"  
✅ VM rebooted successfully  
✅ AD Users and Computers shows linkedin.local domain  
✅ Replication partner shows DC01  
✅ DNS resolves linkedin.local  
✅ SYSVOL and NETLOGON shares exist  

---

**Need detailed steps?** See `PORTING-GUIDE-IAAC-V2.md` for comprehensive guide.

*Quick Start Version: 1.0*
