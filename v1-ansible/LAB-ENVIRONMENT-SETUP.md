# Lab Environment Setup - DC01 & DC02

**Created**: January 15, 2026  
**Purpose**: Azure-based lab environment for testing DC promotion automation

---

## 🎯 Overview

This document describes the lab environment setup with two Azure VMs (DC01 and DC02) integrated with the Ansible DC promotion pipeline.

---

## 🖥️ Lab Infrastructure

### Domain Controllers

| DC | Public IP | Private IP | VNet | Resource Group | Status |
|----|-----------|------------|------|----------------|--------|
| **DC01** | 4.234.159.63 | 10.0.0.6 | DC01-vnet (10.0.0.0/16) | VAMDEVTEST | ✅ Configured |
| **DC02** | 20.108.4.144 | 10.1.0.6 | DC02-vnet (10.1.0.0/16) | VAMDEVTEST | 🆕 New (Terraform) |

### Domain Information
- **Domain**: linkedin.local
- **NetBIOS**: LINKEDIN
- **Forest**: linkedin.local
- **Primary DC**: DC01 (10.0.0.6)

---

## 📁 Files Updated/Created

### 1. Ansible Vault (`inventory/group_vars/all/vault.yml`)

**Added credentials for lab DCs:**
```yaml
# DC01 - Original lab DC
vault_dc01_ip: "4.234.159.63"
vault_dc01_user: "vamdev"
vault_dc01_password: "CHANGE_ME_IN_VAULT"

# DC02 - Terraform cloned DC
vault_dc02_ip: "20.108.4.144"
vault_dc02_user: "vamdev"
vault_dc02_password: "ChangeMe123!@#"

# Lab Domain credentials
vault_lab_domain_admin: "linkedin\\Administrator"
vault_lab_domain_password: "CHANGE_ME_IN_VAULT"
vault_lab_dsrm_password: "CHANGE_ME_IN_VAULT"
```

### 2. Lab Inventory (`inventory/lab/hosts.yml`)

**New inventory file for lab environment:**
- DC01 and DC02 host definitions
- WinRM connection settings (NTLM transport)
- Lab-specific variables
- Azure resource information

### 3. Test Script (`scripts/test-lab-connectivity.sh`)

**New connectivity test script:**
- Tests network ports (5985, 636, 3389)
- Tests Ansible WinRM connectivity
- Provides troubleshooting guidance

### 4. Documentation (`inventory/lab/README.md`)

**Complete lab environment documentation:**
- DC specifications
- Usage examples
- Troubleshooting guide
- Next steps for DC promotion

---

## 🚀 Quick Start

### Step 1: Start the VMs

```bash
# Start DC01
cd "/Volumes/Vamdev Data/Downloads/Projects/LinkedIn - Azure DC Management/scripts"
./start-dc01.sh

# Start DC02
az vm start --resource-group VAMDEVTEST --name DC02
```

### Step 2: Update Vault Passwords

```bash
cd "/Volumes/Vamdev Data/Downloads/Projects/LinkedIn - DC IaaC Build"

# Edit vault (will prompt for vault password)
ansible-vault edit inventory/group_vars/all/vault.yml

# Update these values:
# - vault_dc01_password: <actual DC01 admin password>
# - vault_dc02_password: ChangeMe123!@# (or your chosen password)
# - vault_lab_domain_admin: linkedin\Administrator
# - vault_lab_domain_password: <actual domain admin password>
# - vault_lab_dsrm_password: <DSRM password>
```

### Step 3: Test Connectivity

```bash
# Run connectivity test
./scripts/test-lab-connectivity.sh

# Or test with Ansible directly
ansible lab_domain -i inventory/lab/hosts.yml -m win_ping --ask-vault-pass
```

### Step 4: Promote DC02 (Optional)

```bash
# Run full DC promotion pipeline on DC02
ansible-playbook playbooks/master-pipeline.yml \
  -i inventory/lab/hosts.yml \
  --limit dc02.linkedin.local \
  --ask-vault-pass

# Or dry-run first
ansible-playbook playbooks/master-pipeline.yml \
  -i inventory/lab/hosts.yml \
  --limit dc02.linkedin.local \
  --check \
  --ask-vault-pass
```

---

## 🔐 Authentication Setup

### WinRM Configuration

**Connection Settings:**
```yaml
ansible_connection: winrm
ansible_port: 5985          # HTTP (use 5986 for HTTPS)
ansible_winrm_transport: ntlm  # NTLM for lab (not Kerberos)
ansible_winrm_server_cert_validation: ignore
```

### Credentials Hierarchy

1. **Local Admin** (for initial connection)
   - DC01: `vamdev` / `vault_dc01_password`
   - DC02: `vamdev` / `vault_dc02_password`

2. **Domain Admin** (for DC promotion)
   - User: `linkedin\Administrator`
   - Password: `vault_lab_domain_password`

---

## 🧪 Testing Commands

### Network Connectivity
```bash
# Test WinRM ports
nc -zv 4.234.159.63 5985    # DC01
nc -zv 20.108.4.144 5985    # DC02

# Test LDAPS (DC01 only, if configured)
nc -zv 4.234.159.63 636
```

### Ansible Connectivity
```bash
# Ping all lab DCs
ansible lab_domain -i inventory/lab/hosts.yml -m win_ping --ask-vault-pass

# Ping specific DC
ansible dc01.linkedin.local -i inventory/lab/hosts.yml -m win_ping --ask-vault-pass
ansible dc02.linkedin.local -i inventory/lab/hosts.yml -m win_ping --ask-vault-pass

# Get system info
ansible dc02.linkedin.local -i inventory/lab/hosts.yml -m setup --ask-vault-pass
```

### PowerShell Commands
```bash
# Run PowerShell command
ansible dc02.linkedin.local -i inventory/lab/hosts.yml \
  -m win_shell \
  -a "Get-ComputerInfo | Select-Object CsName, OsName, OsVersion" \
  --ask-vault-pass
```

---

## 🛠️ DC02 Preparation (Before Promotion)

Before promoting DC02 to a domain controller, you need to:

### 1. Enable WinRM (if not already enabled)

RDP to DC02 and run:
```powershell
# Enable WinRM
Enable-PSRemoting -Force

# Allow HTTP
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true

# Configure firewall
New-NetFirewallRule -DisplayName "WinRM HTTP" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow

# Restart WinRM
Restart-Service WinRM
```

### 2. Configure DNS to Point to DC01

```powershell
# Set DNS to DC01
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "10.0.0.6","8.8.8.8"

# Verify
Get-DnsClientServerAddress -AddressFamily IPv4

# Test resolution
nslookup dc01.linkedin.local
nslookup linkedin.local
```

### 3. Join Domain (if not using Ansible)

```powershell
# Join domain
$credential = Get-Credential -UserName "linkedin\Administrator" -Message "Enter domain admin password"
Add-Computer -DomainName "linkedin.local" -Credential $credential -Restart
```

---

## 📊 Inventory Structure

```
inventory/
├── group_vars/
│   └── all/
│       └── vault.yml          ← Updated with DC01/DC02 credentials
├── production/
│   └── hosts.yml              ← Production DCs (unchanged)
├── staging/
│   └── hosts.yml              ← Staging DCs (unchanged)
└── lab/                       ← NEW
    ├── hosts.yml              ← Lab DCs (DC01 & DC02)
    └── README.md              ← Lab documentation
```

---

## 🔧 Troubleshooting

### Issue: "Connection refused" on port 5985

**Solutions:**
1. Ensure VM is running
2. Enable WinRM on the VM (see preparation steps)
3. Check Azure NSG allows port 5985
4. Verify Windows Firewall allows WinRM

### Issue: "Authentication failed"

**Solutions:**
1. Verify vault password is correct
2. Check username/password in vault.yml
3. Ensure NTLM auth is enabled on VM
4. Try with explicit credentials:
   ```bash
   ansible dc02.linkedin.local -i inventory/lab/hosts.yml -m win_ping \
     -e ansible_user=vamdev -e ansible_password='YourPassword'
   ```

### Issue: "Cannot resolve hostname"

**Solutions:**
1. Use IP addresses instead of hostnames
2. Add entries to /etc/hosts:
   ```bash
   sudo sh -c 'echo "4.234.159.63 dc01.linkedin.local dc01" >> /etc/hosts'
   sudo sh -c 'echo "20.108.4.144 dc02.linkedin.local dc02" >> /etc/hosts'
   ```

### Issue: DC promotion fails

**Common causes:**
1. DC02 not joined to domain
2. DNS not pointing to DC01
3. Domain admin credentials incorrect
4. Network connectivity issues between DCs

---

## 💰 Cost Management

**Remember to stop VMs when not in use:**

```bash
# Stop DC01
az vm deallocate --resource-group VAMDEVTEST --name DC01

# Stop DC02
az vm deallocate --resource-group VAMDEVTEST --name DC02

# Check status
az vm list --resource-group VAMDEVTEST --query "[].{Name:name, PowerState:powerState}" -o table
```

**Estimated costs when running:**
- Each VM: ~$0.20-0.30/hour
- Storage: ~$20/month per VM
- Public IPs: ~$3/month each

---

## 📚 Related Documentation

- **Terraform Configuration**: `LinkedIn - Azure DC Management/terraform-dc-clone/`
- **Azure VM Management**: `LinkedIn - Azure DC Management/scripts/`
- **DC Promotion Playbooks**: `playbooks/master-pipeline.yml`
- **Ansible Roles**: `roles/dc-promotion/`, `roles/dc-health-checks/`, etc.

---

## ✅ Verification Checklist

Before running DC promotion on DC02:

- [ ] DC01 is running and accessible
- [ ] DC02 is running and accessible
- [ ] WinRM enabled on DC02 (port 5985)
- [ ] DNS on DC02 points to DC01 (10.0.0.6)
- [ ] DC02 joined to linkedin.local domain
- [ ] Vault passwords updated with actual values
- [ ] Ansible connectivity test passes
- [ ] Network connectivity between DC01 and DC02 verified

---

**Status**: ✅ Lab environment configured and ready for testing  
**Next Step**: Test Ansible connectivity and optionally promote DC02 to DC
