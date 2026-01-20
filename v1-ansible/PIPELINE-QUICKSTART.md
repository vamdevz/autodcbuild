# DC Promotion Pipeline - Quick Start

## 🚀 Quick Deploy

### Staging
```bash
./scripts/run-dc-promotion.sh -e staging -t stg-dc01.staging.linkedin.biz
```

### Production (with confirmation)
```bash
./scripts/run-dc-promotion.sh -e production -t lva1-dc03.linkedin.biz
```

### Dry-Run (Check Mode)
```bash
./scripts/run-dc-promotion.sh -e production -t lva1-dc03.linkedin.biz --check
```

---

## 📋 Prerequisites

1. **Ansible installed** (2.9+)
   ```bash
   pip install ansible pywinrm
   ```

2. **Kerberos configured** for WinRM
   ```bash
   # macOS
   brew install krb5
   
   # Configure /etc/krb5.conf with LinkedIn domains
   ```

3. **Set up Ansible Vault** (first time only)
   ```bash
   ./scripts/setup-ansible-vault.sh
   
   # Edit vault and add real credentials
   ansible-vault edit inventory/group_vars/all/vault.yml
   ```

4. **Make scripts executable**
   ```bash
   chmod +x scripts/*.sh
   ```

---

## 🔐 Vault Management

### Edit encrypted credentials
```bash
ansible-vault edit inventory/group_vars/all/vault.yml
```

### View without editing
```bash
ansible-vault view inventory/group_vars/all/vault.yml
```

### Create password file (avoid typing each time)
```bash
echo 'your-vault-password' > ~/.ansible-vault-pass
chmod 600 ~/.ansible-vault-pass
```

---

## 🧪 Testing & Validation

### Validate DC health (post-promotion)
```bash
./scripts/validate-dc-health.sh production lva1-dc03.linkedin.biz
```

### Run specific role only
```bash
ansible-playbook playbooks/master-pipeline.yml \
  -i inventory/staging/hosts.yml \
  --limit stg-dc01.staging.linkedin.biz \
  --tags "pre-check"
```

### Available tags:
- `pre-check` - Pre-promotion validation only
- `promotion` - DC promotion step
- `health-check` - Post-promotion health validation
- `dns-check` - DNS configuration
- `auth-check` - Authentication validation
- `agents` - Agent installation
- `post-check` - Final reporting

---

## 📁 Project Structure

```
linkedin-pam/
├── playbooks/
│   └── master-pipeline.yml          # Main orchestration playbook
├── roles/
│   ├── pre-promotion-check/         # Domain join validation
│   ├── dc-promotion/                # Actual dcpromo
│   ├── reboot-handler/              # Post-promo reboot
│   ├── dc-health-checks/            # dcdiag, repadmin
│   ├── dns-configuration/           # Conditional forwarders
│   ├── authentication-check/        # Event log validation
│   ├── agent-installation/          # 5 security agents
│   └── post-checks/                 # Certificate, reporting
├── inventory/
│   ├── staging/hosts.yml
│   ├── production/hosts.yml
│   └── group_vars/all/vault.yml     # Encrypted secrets
├── scripts/
│   ├── run-dc-promotion.sh          # Main deployment script
│   ├── Run-DCPromotion.ps1          # PowerShell version
│   ├── validate-dc-health.sh        # Health check only
│   └── setup-ansible-vault.sh       # Vault initialization
└── ansible.cfg                      # Ansible config
```

---

## 🎯 Deployment Workflow

1. **Pre-Checks**
   - Verify domain membership
   - Check DNS configuration
   - Validate disk space
   - Test DC connectivity

2. **DC Promotion**
   - Install AD DS role
   - Run `dcpromo` (add to existing domain)
   - Configure database/SYSVOL paths

3. **Reboot & Validation**
   - Automatic reboot
   - Wait for AD services
   - Verify service health

4. **Health Checks**
   - SYSVOL/NETLOGON shares
   - Replication status (`repadmin`)
   - Full `dcdiag` suite
   - DNS tests

5. **DNS Configuration**
   - Create conditional forwarders
   - Verify name resolution
   - Domain-specific zones

6. **Authentication Check**
   - Monitor Event IDs (4624, 4768, 4771)
   - Validate Kerberos/NTLM

7. **Agent Installation**
   - .NET Framework 4.8
   - Azure AD Password Protection
   - Azure ATP Sensor
   - Quest Change Auditor
   - Validate Qualys version

8. **Post-Checks**
   - Add to LDAPS group
   - Trigger cert enrollment
   - Generate final report

---

## 🔍 Troubleshooting

### WinRM connection issues
```bash
# Test WinRM connectivity
ansible windows -i inventory/staging/hosts.yml -m win_ping

# Verify Kerberos
klist
kinit your-username@LINKEDIN.BIZ
```

### Check Ansible syntax
```bash
ansible-playbook playbooks/master-pipeline.yml --syntax-check
```

### Verbose output
```bash
./scripts/run-dc-promotion.sh -e staging -t stg-dc01 -vvv
```

### Vault issues
```bash
# Re-encrypt vault
ansible-vault rekey inventory/group_vars/all/vault.yml

# Decrypt for editing (temporarily)
ansible-vault decrypt inventory/group_vars/all/vault.yml
# ... edit ...
ansible-vault encrypt inventory/group_vars/all/vault.yml
```

---

## 📝 Manual Steps (Post-Deployment)

After automation completes:

1. **Verify certificate issued**: [go/incerts](http://go/incerts)
2. **Confirm FIM compliance**: Contact InfoSec SPM team
   - Qualys version check (must be ≥ 6.2.5.4)
3. **Update change ticket**: Document completion
4. **Monitor agents**: Wait 5-10 minutes for initialization

---

## 🔒 Security Notes

- All credentials stored in encrypted Ansible Vault
- WinRM uses Kerberos authentication
- Service principal with least-privilege access
- Change tickets required for production
- Manual verification checkpoints enforced

---

## 📞 Support

For issues or questions:
- **AD Operations Team**: ad-ops@linkedin.com
- **Automation Support**: infra-automation@linkedin.com
- **InfoSec (FIM/Compliance)**: infosec-spm@linkedin.com

---

## 📚 Additional Documentation

- Full architecture: [`DC-BUILD-PROMOTION-PROJECT.md`](DC-BUILD-PROMOTION-PROJECT.md)
- LinkedIn workflow: [`LINKEDIN-DC-PROMOTION-SUMMARY.md`](LINKEDIN-DC-PROMOTION-SUMMARY.md)
- Workflow visual: [`linkedin-dc-promotion-workflow.html`](linkedin-dc-promotion-workflow.html)
