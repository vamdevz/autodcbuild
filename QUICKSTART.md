# Quick Start Guide - DC Automation

## Create a New DC in 3 Steps

### Step 1: Trigger Workflow

**Via GitHub UI**:
1. Go to https://github.com/vamdevz/autodcbuild/actions
2. Click "Full DC Automation"
3. Click "Run workflow"
4. Enter VM name (e.g., `DC03`)
5. Click "Run workflow" button

**Via GitHub CLI**:
```bash
gh workflow run full-dc-automation.yml \
  --repo vamdevz/autodcbuild \
  -f vm_name="DC03"
```

### Step 2: Wait ~7 Minutes

Monitor progress:
```bash
gh run list --repo vamdevz/autodcbuild
gh run watch <run-id> --repo vamdevz/autodcbuild
```

### Step 3: Verify & Use

```bash
# Get DC IP
az vm show --resource-group VAMDEVTEST --name DC03 --show-details --query publicIps -o tsv

# RDP to new DC
mstsc /v:<ip-address>

# Login with:
Username: linkedin.local\vamdev
Password: (your domain admin password)
```

---

## Common Commands

### Create DC
```bash
gh workflow run full-dc-automation.yml --repo vamdevz/autodcbuild -f vm_name="DC04"
```

### Create VM Only
```bash
gh workflow run create-vm.yml --repo vamdevz/autodcbuild -f vm_name="Server01"
```

### Promote Existing VM
```bash
gh workflow run deploy-lab.yml --repo vamdevz/autodcbuild -f vm_name="ExistingVM"
```

### Check DC Status
```bash
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts "Get-Service NTDS,DNS,Netlogon | Format-Table"
```

### Get VM Info
```bash
az vm show --resource-group VAMDEVTEST --name DC03 --show-details \
  --query '{Name:name, IP:publicIps, State:powerState}' -o table
```

### Delete DC (Cleanup)
```bash
# Demote first (optional)
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts "Uninstall-ADDSDomainController -Force"

# Delete VM and resources
az vm delete --resource-group VAMDEVTEST --name DC03 --yes
az disk delete --resource-group VAMDEVTEST --name DC03_OsDisk --yes --no-wait
az network nic delete --resource-group VAMDEVTEST --name DC03-nic --no-wait
az network public-ip delete --resource-group VAMDEVTEST --name DC03-pip --no-wait
az network nsg delete --resource-group VAMDEVTEST --name DC03-nsg --no-wait
```

---

## Troubleshooting Quick Fixes

### Workflow Failed?
```bash
# View logs
gh run view <run-id> --repo vamdevz/autodcbuild --log-failed
```

### Can't RDP?
```bash
# Check if VM is running
az vm get-instance-view --resource-group VAMDEVTEST --name DC03 \
  --query 'instanceView.statuses[?starts_with(code, `PowerState`)].displayStatus' -o tsv

# Restart VM
az vm restart --resource-group VAMDEVTEST --name DC03
```

### DNS Issues?
```bash
# Fix DNS on VM
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts "Set-DnsClientServerAddress -InterfaceAlias 'Ethernet*' -ServerAddresses 10.0.0.6,8.8.8.8"
```

### Check AD Services?
```bash
az vm run-command invoke \
  --resource-group VAMDEVTEST \
  --name DC03 \
  --command-id RunPowerShellScript \
  --scripts "Get-Service NTDS,DNS,Netlogon,KDC | Format-Table Status,Name"
```

---

## Expected Timeline

| Stage | Duration | What's Happening |
|-------|----------|------------------|
| VM Creation | 2-3 min | Creating VM, NSG, NIC, Public IP |
| WinRM Setup | 30 sec | Configuring remote management |
| AD DS Install | 1 min | Installing AD Role |
| DNS Config | 10 sec | Setting DNS to DC01 |
| DC Promotion | 3-4 min | Promoting to DC, replication |
| **Total** | **~7 min** | **Complete DC ready** |

---

## Credentials Reference

| Purpose | Username | Password Location |
|---------|----------|-------------------|
| Local Admin | `azureuser` | GitHub Secret: `DOMAIN_ADMIN_PASSWORD` |
| Domain Admin | `linkedin.local\vamdev` | GitHub Secret: `DOMAIN_ADMIN_PASSWORD` |
| DSRM | `(local admin)` | GitHub Secret: `SAFE_MODE_PASSWORD` |

---

## Success Indicators

✅ **VM Created Successfully**:
- Workflow shows "create-vm" job completed
- VM visible in Azure Portal
- Can RDP with local admin

✅ **DC Promotion Successful**:
- Workflow shows "DC PROMOTION SUCCESSFUL!"
- NTDS service running
- Can login with domain credentials
- Shows in AD Sites and Services

---

## Need Help?

1. ✅ **Check [README.md](README.md)** for detailed docs
2. ✅ **View workflow logs** in GitHub Actions
3. ✅ **Test manually via RDP** if workflow unclear
4. ✅ **Check Azure Portal** for resource status

---

**That's it! You're ready to create DCs! 🚀**
