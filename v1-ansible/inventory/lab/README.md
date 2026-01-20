# Lab Environment Inventory

This inventory is for the **Azure-based lab environment** with DC01 and DC02.

## 🖥️ Lab Domain Controllers

| DC | Public IP | Private IP | VM Name | Status |
|----|-----------|------------|---------|--------|
| **DC01** | 4.234.159.63 | 10.0.0.6 | DC01 | Original lab DC |
| **DC02** | 20.108.4.144 | 10.1.0.6 | DC02 | Terraform clone |

## 🌐 Domain Information

- **Domain**: linkedin.local
- **NetBIOS**: LINKEDIN
- **Forest Functional Level**: Windows Server 2019
- **Domain Functional Level**: Windows Server 2019

## 🔐 Authentication

### WinRM Connection
- **Transport**: NTLM (lab environment, not Kerberos)
- **Port**: 5985 (HTTP) or 5986 (HTTPS)
- **Cert Validation**: Disabled for lab

### Credentials (from vault)
- **Local Admin**: `vault_dc01_user` / `vault_dc01_password` (DC01)
- **Local Admin**: `vault_dc02_user` / `vault_dc02_password` (DC02)
- **Domain Admin**: `vault_lab_domain_admin` / `vault_lab_domain_password`

## 🚀 Usage

### Test Connectivity
```bash
cd "/Volumes/Vamdev Data/Downloads/Projects/LinkedIn - DC IaaC Build"

# Ping DC01
ansible lab_domain -i inventory/lab/hosts.yml -m win_ping

# Ping specific DC
ansible dc01.linkedin.local -i inventory/lab/hosts.yml -m win_ping
ansible dc02.linkedin.local -i inventory/lab/hosts.yml -m win_ping
```

### Run Playbooks
```bash
# Run against lab environment
ansible-playbook playbooks/master-pipeline.yml \
  -i inventory/lab/hosts.yml \
  --limit dc02.linkedin.local \
  --ask-vault-pass

# Dry run (check mode)
ansible-playbook playbooks/master-pipeline.yml \
  -i inventory/lab/hosts.yml \
  --limit dc02.linkedin.local \
  --check
```

### Gather Facts
```bash
# Get system info
ansible lab_domain -i inventory/lab/hosts.yml \
  -m setup \
  --ask-vault-pass
```

## 📝 Before Using

1. **Ensure VMs are running**:
   ```bash
   # Start DC01
   cd "/Volumes/Vamdev Data/Downloads/Projects/LinkedIn - Azure DC Management/scripts"
   ./start-dc01.sh
   
   # Start DC02
   az vm start --resource-group VAMDEVTEST --name DC02
   ```

2. **Update vault with actual passwords**:
   ```bash
   ansible-vault edit inventory/group_vars/all/vault.yml
   # Update:
   # - vault_dc01_password
   # - vault_dc02_password  
   # - vault_lab_domain_admin
   # - vault_lab_domain_password
   # - vault_lab_dsrm_password
   ```

3. **Test WinRM connectivity**:
   ```bash
   # From your Mac
   nc -zv 4.234.159.63 5985    # DC01
   nc -zv 20.108.4.144 5985    # DC02
   ```

## ⚠️ Important Notes

### DC01 (Original)
- Already configured as Domain Controller
- Domain: linkedin.local
- LDAPS enabled on port 636
- Used by PAM application for testing

### DC02 (New Clone)
- Fresh Windows Server 2019 installation
- **NOT yet promoted to DC**
- Same specs as DC01
- Ready for DC promotion via Ansible

## 🎯 Next Steps

### To Promote DC02 to Domain Controller:

1. **Ensure DC01 is running** (primary DC)
2. **Configure DC02 DNS** to point to DC01 (10.0.0.6)
3. **Join DC02 to domain** (linkedin.local)
4. **Run DC promotion playbook**:
   ```bash
   ansible-playbook playbooks/master-pipeline.yml \
     -i inventory/lab/hosts.yml \
     --limit dc02.linkedin.local \
     --ask-vault-pass
   ```

## 🔧 Troubleshooting

### WinRM Connection Issues
```bash
# Test WinRM from Python
python3 << 'EOF'
import winrm
session = winrm.Session('http://20.108.4.144:5985/wsman', 
                        auth=('vamdev', 'ChangeMe123!@#'))
result = session.run_cmd('ipconfig')
print(result.std_out.decode())
EOF
```

### DNS Issues
If DC02 can't reach DC01:
1. RDP to DC02
2. Set DNS: `Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "10.0.0.6","8.8.8.8"`
3. Test: `nslookup dc01.linkedin.local`

### NSG Rules
Ensure Azure NSG allows:
- Port 5985 (WinRM HTTP)
- Port 5986 (WinRM HTTPS)
- Port 3389 (RDP)
- Port 636 (LDAPS) if needed

---

**Created**: January 15, 2026  
**Environment**: Azure Lab (VAMDEVTEST)  
**Purpose**: Testing DC promotion automation
