# Post-Promotion Tasks and Configuration

This document outlines all tasks required after DC promotion, categorized by automation capability.

---

## 📋 Task Categories

- ✅ **Automated** - Fully automated in workflow
- 🔄 **Scriptable** - Can be scripted but requires parameters/manual trigger
- ⚠️ **Manual** - Requires human intervention

---

## ✅ AUTOMATED TASKS (Included in Workflow)

These tasks run automatically after DC promotion completes.

### 1. Health Status Checks
**Script**: `post-promotion-checks.ps1`  
**Status**: ✅ Fully Automated  
**Duration**: ~2-3 minutes

**Checks Performed**:
- ✅ SYSVOL and Netlogon shares
- ✅ AD Replication status (`repadmin /showrepl`)
- ✅ Replication queue (`repadmin /queue`)
- ✅ DCDiag tests:
  - DCPromo validation
  - RegisterInDNS test
  - General DCDiag
  - DNS-specific tests
- ✅ AD Services status (NTDS, DNS, Netlogon, KDC)
- ✅ DNS Server configuration
- ✅ LDAP/LDAPS port availability
- ✅ Computer object location in AD

**How to Run Manually**:
```bash
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts @v2-github-actions/scripts/post-promotion-checks.ps1
```

**Expected Output**:
```
========================================
  HEALTH CHECK SUMMARY
========================================

  Passed:  8 / 8
  Warnings: 0 / 8
  Failed:  0 / 8

  [OK] Shares: PASS
  [OK] Replication: PASS
  [OK] Queue: PASS
  ...

Overall Status: HEALTHY
```

---

## 🔄 SCRIPTABLE TASKS (Run on Demand)

### 2. DNS Conditional Forwarders
**Script**: `configure-dns-forwarders.ps1`  
**Status**: 🔄 Scriptable (requires domain type parameter)  
**Duration**: ~1 minute

**Configuration by Domain**:

#### For linkedin.local (Lab):
```powershell
# Microsoft services only
./configure-dns-forwarders.ps1 -DomainType local
```

**Forwarders Created**:
- `gtm.corp.microsoft.com` → 172.31.197.245, 172.31.197.246, 172.31.197.80, 172.31.197.81
- `sts.microsoft.com` → 172.31.197.245, 172.31.197.246, 172.31.197.80, 172.31.197.81

#### For linkedin.biz (Production):
```powershell
./configure-dns-forwarders.ps1 -DomainType biz
```

**Additional Forwarders**:
- `internal.linkedin.cn` → 10.44.71.6, 10.44.71.5

#### For internal.linkedin.cn (China):
```powershell
./configure-dns-forwarders.ps1 -DomainType china
```

**Additional Forwarders**:
- `linkedin.biz` → 10.41.63.5, 10.41.63.6, 172.21.2.103, 172.21.2.104

**Run via GitHub Actions**:
```bash
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts @v2-github-actions/scripts/configure-dns-forwarders.ps1 \
  --parameters "DomainType=local"
```

### 3. DNS Resolution Testing
**Status**: 🔄 Scriptable (included in forwarder script)

**Automatic Tests**:
```powershell
# Test resolution (included in configure-dns-forwarders.ps1)
Resolve-DnsName sts.microsoft.com
Resolve-DnsName gtm.corp.microsoft.com
nslookup msft.sts.microsoft.com
```

**Manual Verification**:
```powershell
# From DC
nslookup msft.sts.microsoft.com
nslookup linkedin.biz        # if in China
nslookup internal.linkedin.cn # if in BIZ
```

### 4. Add to Security Group
**Status**: 🔄 Scriptable (requires elevated permissions)

**PowerShell Command**:
```powershell
# Add DC to LDAPS auto-enroll group
Add-ADGroupMember -Identity "SG-LDAPS-DomainController-AutoEnroll" `
  -Members (Get-ADComputer -Identity $env:COMPUTERNAME)
```

**Verification**:
```powershell
# Check group membership
Get-ADComputer -Identity DC03 -Properties MemberOf | 
  Select-Object -ExpandProperty MemberOf | 
  Where-Object { $_ -match "LDAPS" }
```

**Run via Workflow** (if needed):
```bash
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts "Add-ADGroupMember -Identity 'SG-LDAPS-DomainController-AutoEnroll' -Members (Get-ADComputer -Identity $env:COMPUTERNAME)"
```

---

## ⚠️ MANUAL TASKS (Require Human Intervention)

### 5. LDAP Bind Test from Client
**Status**: ⚠️ Manual (requires external client machine)  
**Duration**: 2-3 minutes

**Linux Client** (SSH):
```bash
# LDAPS bind test
ldapsearch -H ldaps://dc03.linkedin.local:636 \
  -D 'your-user@linkedin.local' \
  -W \
  -b 'dc=linkedin,dc=local' \
  -x 'cn=Your Name' co
```

**Windows Client** (PowerShell):
```powershell
# LDAP test
[adsi]"LDAP://dc03.linkedin.local:389"

# LDAPS test
[adsi]"LDAPS://dc03.linkedin.local:636"
```

**Expected Result**:
- LDAP (389): Should connect successfully
- LDAPS (636): May fail until certificate enrolled

---

### 6. Azure Portal Verification
**Status**: ⚠️ Manual (requires Azure Portal access)  
**Duration**: 5 minutes

**Steps**:
1. Login to Azure Portal
2. Navigate to Log Analytics workspace
3. Run KQL query:

```kql
SecurityEvent
| where Computer in ("dc03.linkedin.local") 
| where EventID == 4624 or EventID == 4768 or EventID == 4771
| take 100
| project TimeGenerated, Computer, EventID, Account, LogonType
| order by TimeGenerated desc
```

**Expected Result**:
- Should see authentication events (4624, 4768, 4771)
- Indicates DC is servicing authentication requests

**Wait Time**: May need 15-30 minutes for logs to appear

---

### 7. Agent Installation
**Status**: ⚠️ Manual (requires installer files and licenses)  
**Duration**: 30-45 minutes  
**Requires Restart**: Yes

#### Prerequisites Check (Automated):
```powershell
# Check existing agents
Get-WmiObject -Class Win32_Product | 
  Where-Object { $_.Name -match "Qualys|Microsoft Monitoring|Azure" }
```

#### Required Agents:
| Agent | Installer Location | Notes |
|-------|-------------------|-------|
| .NET Framework 4.8 | Windows Update | Required first, restart needed |
| Azure AD Password Protection | `\\lva1-adc01.linkedin.biz\c$\Temp` | Restart required |
| Azure ATP Sensor | `\\lva1-adc01.linkedin.biz\c$\Temp` | - |
| Quest Change Auditor | `\\lva1-adc01.linkedin.biz\c$\Temp` | - |
| Qualys Agent | Pre-installed | Verify version ≥ 6.2.5.4 |
| Microsoft Monitoring Agent | Pre-installed | - |

#### Installation Steps:
```powershell
# 1. Check installed applications
appwiz.cpl

# 2. Copy installers from share
Copy-Item \\lva1-adc01.linkedin.biz\c$\Temp\* C:\Temp\

# 3. Install .NET Framework 4.8
# Run installer, restart required

# 4. Install Azure AD Password Protection DC Agent
# Run installer, select "restart later"

# 5. Install Azure ATP Sensor
# Run installer

# 6. Install Quest Change Auditor
# Run installer

# 7. Restart with tracking comment
shutdown /r /c "ChangeTicket - DC03 DC Promotion"

# 8. After restart, verify services
Get-Service -Name AzureADPasswordProtectionDCAgent, `
  QualysAgent, NPSrvHost, HealthService, AATPSensor
```

**Notes**:
- Some services may show "Stopped" initially (normal during initialization)
- Wait 5-10 minutes after installation for services to start
- Check with InfoSec SPM team for FIM compliance

---

### 8. Certificate Enrollment
**Status**: ⚠️ Manual (requires go/incerts portal access)  
**Duration**: 15-30 minutes (includes approval time)

#### Prerequisites:
1. ✅ DC added to `SG-LDAPS-DomainController-AutoEnroll` group
2. ✅ Group Policy applied (may need `gpupdate /force`)

#### Steps:
1. **Via go/incerts Portal**:
   - Navigate to go/incerts
   - Request domain controller certificate
   - Specify FQDN: `dc03.linkedin.local`
   - Submit request
   - Wait for approval

2. **Verify Auto-Enrollment**:
   ```powershell
   # Check certificate store
   Get-ChildItem Cert:\LocalMachine\My | 
     Where-Object { $_.Subject -match $env:COMPUTERNAME }
   
   # Force GP update
   gpupdate /force
   
   # Check auto-enrollment status
   certutil -pulse
   ```

3. **Test LDAPS After Certificate**:
   ```powershell
   # Test LDAPS port
   Test-NetConnection -ComputerName localhost -Port 636
   
   # Test LDAPS binding
   [adsi]"LDAPS://dc03.linkedin.local:636"
   ```

**Expected Timeline**:
- Certificate request: 5 minutes
- Approval wait: 10-20 minutes
- Auto-enrollment: 5 minutes
- Total: 20-30 minutes

---

## 🔄 WORKFLOW INTEGRATION

### Current Automation Status

The `deploy-lab.yml` workflow currently includes:
1. ✅ AD DS Role installation
2. ✅ DNS configuration
3. ✅ DC promotion
4. ✅ Basic success verification

### Proposed Enhancement

Add post-promotion tasks to `deploy-lab.yml`:

```yaml
- name: Post-Promotion Health Checks
  shell: bash
  env:
    VM_NAME: ${{ inputs.vm_name }}
  run: |
    echo "Running post-promotion health checks..."
    
    az vm run-command invoke \
      --resource-group VAMDEVTEST \
      --name "$VM_NAME" \
      --command-id RunPowerShellScript \
      --scripts @v2-github-actions/scripts/post-promotion-checks.ps1 \
      -o json | jq -r '.value[0].message'

- name: Configure DNS Forwarders (Lab)
  shell: bash
  env:
    VM_NAME: ${{ inputs.vm_name }}
  run: |
    echo "Configuring DNS conditional forwarders..."
    
    az vm run-command invoke \
      --resource-group VAMDEVTEST \
      --name "$VM_NAME" \
      --command-id RunPowerShellScript \
      --scripts @v2-github-actions/scripts/configure-dns-forwarders.ps1 \
      --parameters "DomainType=local" \
      -o json | jq -r '.value[0].message'

- name: Add to LDAPS Security Group
  shell: bash
  env:
    VM_NAME: ${{ inputs.vm_name }}
  run: |
    echo "Adding DC to LDAPS auto-enroll group..."
    
    az vm run-command invoke \
      --resource-group VAMDEVTEST \
      --name "$VM_NAME" \
      --command-id RunPowerShellScript \
      --scripts "Add-ADGroupMember -Identity 'SG-LDAPS-DomainController-AutoEnroll' -Members (Get-ADComputer -Identity \$env:COMPUTERNAME) -ErrorAction SilentlyContinue"
```

---

## 📋 POST-PROMOTION CHECKLIST

### Immediate (Automated):
- [x] SYSVOL and Netlogon shares present
- [x] AD Replication working
- [x] Replication queue empty
- [x] DCDiag tests passed
- [x] AD Services running
- [x] DNS Server operational
- [x] LDAP port (389) accessible

### Short-term (Scriptable):
- [ ] DNS conditional forwarders configured
- [ ] DNS resolution tests passed
- [ ] Added to LDAPS security group
- [ ] Group Policy updated

### Long-term (Manual):
- [ ] LDAP bind test from client (Linux/Windows)
- [ ] Azure Portal authentication logs visible
- [ ] .NET Framework 4.8 installed
- [ ] Azure AD Password Protection installed
- [ ] Azure ATP Sensor installed
- [ ] Quest Change Auditor installed
- [ ] All agent services running
- [ ] Certificate requested via go/incerts
- [ ] Certificate enrolled and LDAPS working
- [ ] InfoSec FIM compliance confirmed

---

## 🚀 Quick Commands

### Run All Automated Checks:
```bash
# Health checks
az vm run-command invoke --resource-group VAMDEVTEST --name DC03 \
  --command-id RunPowerShellScript \
  --scripts @v2-github-actions/scripts/post-promotion-checks.ps1

# DNS forwarders (lab)
az vm run-command invoke --resource-group VAMDEVTEST --name DC03 \
  --command-id RunPowerShellScript \
  --scripts @v2-github-actions/scripts/configure-dns-forwarders.ps1 \
  --parameters "DomainType=local"
```

### Verify DC Status:
```bash
# Quick status
az vm run-command invoke --resource-group VAMDEVTEST --name DC03 \
  --command-id RunPowerShellScript \
  --scripts "Get-Service NTDS,DNS,Netlogon,KDC | Format-Table Status,Name"
```

---

## 📊 Automation Summary

| Category | Count | Automation % |
|----------|-------|--------------|
| **Automated** | 8 tasks | 100% |
| **Scriptable** | 4 tasks | 75% (need manual trigger) |
| **Manual** | 4 tasks | 0% (require human) |
| **Total** | 16 tasks | 60% automatable |

**Time Savings**:
- Manual execution: ~90 minutes
- Automated execution: ~5 minutes + ~45 minutes manual (agents/certs)
- **Savings: ~45 minutes per DC**

---

## 🔍 Troubleshooting

### Health Check Failed?
```bash
# Re-run with detailed output
az vm run-command invoke --resource-group VAMDEVTEST --name DC03 \
  --command-id RunPowerShellScript \
  --scripts @v2-github-actions/scripts/post-promotion-checks.ps1 \
  --query 'value[0].message' -o tsv
```

### Replication Issues?
```powershell
# On DC
repadmin /showrepl
repadmin /replsummary
dcdiag /test:replications
```

### DNS Forwarder Fails?
```powershell
# Check DNS service
Get-Service DNS

# List existing forwarders
Get-DnsServerZone | Where-Object { $_.ZoneType -eq 'Forwarder' }

# Test resolution
Resolve-DnsName sts.microsoft.com
```

---

**Next Steps**: Add post-promotion tasks to workflow or run manually as needed.
