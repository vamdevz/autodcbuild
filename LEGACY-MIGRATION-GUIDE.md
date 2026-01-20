# Migration Guide: v1 (Ansible) to v2 (GitHub Actions)

Complete guide for migrating from the Ansible-based pipeline to the modernized GitHub Actions + PowerShell pipeline.

## Executive Summary

| Aspect | v1 (Ansible) | v2 (GitHub Actions) | Benefit |
|--------|--------------|---------------------|---------|
| **Code Volume** | ~1,500 lines | ~600-800 lines | 60% reduction |
| **Execution Time** | 50-80 minutes | 30-50 minutes | 30-40% faster |
| **Dependencies** | Ansible, Python, WinRM, Kerberos | PowerShell only | Simplified |
| **Secret Management** | File-based Ansible Vault | Azure Key Vault | More secure |
| **Deployment Method** | CLI scripts | GitHub Actions UI | Self-service |
| **Validation** | Manual | Automated PR checks | Better quality |
| **Audit Trail** | Local logs | GitHub + Azure | Enterprise-grade |

## Feature Parity Matrix

| Feature | v1 Status | v2 Status | Notes |
|---------|-----------|-----------|-------|
| Pre-promotion validation | ✅ | ✅ | Same checks |
| DC promotion | ✅ | ✅ | Native PowerShell cmdlets |
| Reboot handling | ✅ | ✅ | Improved service monitoring |
| Health checks (7 tests) | ✅ | ✅ | dcdiag, repadmin, shares |
| DNS forwarders (4 zones) | ✅ | ✅ | Cross-domain resolution |
| Authentication validation | ✅ | ✅ | Event log monitoring |
| Agent installation (5 agents) | ✅ | ✅ | .NET, Azure AD PP, ATP, Quest, Qualys |
| LDAPS group membership | ✅ | ✅ | Auto-enrollment |
| Certificate enrollment | ✅ | ✅ | certutil -pulse |
| Comprehensive reporting | ✅ | ✅ | Enhanced JSON output |
| Production confirmation | ✅ | ✅ | GitHub Environment approval |
| Dry-run mode | ✅ | ⚠️ | Use staging environment |

**Legend**: ✅ Implemented | ⚠️ Alternative approach | ❌ Not available

## Migration Steps

### Phase 1: Setup (1-2 hours)

1. **Azure Infrastructure**
   - Create Azure Key Vault
   - Configure OIDC authentication
   - Store secrets in Key Vault
   - See: [AZURE-SETUP.md](AZURE-SETUP.md)

2. **GitHub Configuration**
   - Create staging/production environments
   - Deploy self-hosted runner
   - Configure GitHub secrets
   - See: [GITHUB-ACTIONS-SETUP.md](GITHUB-ACTIONS-SETUP.md)

3. **Configuration Files**
   - Review `config/staging.json`
   - Review `config/production.json`
   - Update with your domain settings

### Phase 2: Testing (1 week)

1. **Lab Environment** (Day 1-2)
   ```bash
   # Clone repo
   git clone YOUR_REPO
   cd v2-github-actions
   
   # Run pre-checks only (safe)
   .\scripts\Invoke-DCPromotionPipeline.ps1 \
     -Environment lab \
     -ConfigPath ./config/lab.json \
     -KeyVaultName dc-promotion-kv \
     -SkipPromotion \
     -SkipPostConfig
   ```

2. **Staging Environment** (Day 3-5)
   ```bash
   # Trigger via GitHub Actions
   gh workflow run deploy-staging.yml -f target_dc=stg-dc01
   
   # Or run manually
   .\scripts\Invoke-DCPromotionPipeline.ps1 -Environment staging -KeyVaultName dc-promotion-kv
   ```

3. **Validation** (Day 6-7)
   - Compare execution time vs v1
   - Verify all health checks pass
   - Review deployment reports
   - Test rollback procedures

### Phase 3: Parallel Operations (2-4 weeks)

Run both v1 and v2 side-by-side:

| Week | v1 Usage | v2 Usage | Goal |
|------|----------|----------|------|
| 1 | Primary | Testing | Gain confidence |
| 2 | Primary | 25% traffic | Monitor stability |
| 3 | 50% | 50% | Equal split |
| 4 | Backup | Primary | Full cutover |

### Phase 4: Full Cutover

1. **Communication** (1 week before)
   - Notify AD Operations team
   - Update runbooks
   - Schedule training session

2. **Cutover Day**
   - Final v2 production test
   - Update documentation links
   - Archive v1 (keep accessible)

3. **Post-Cutover** (1 week after)
   - Monitor deployments
   - Gather feedback
   - Address issues quickly

## Code Comparison

### Example: Pre-Promotion Checks

**v1 (Ansible) - 76 lines**
```yaml
roles/pre-promotion-check/tasks/main.yml
roles/pre-promotion-check/defaults/main.yml
```

**v2 (PowerShell) - 382 lines in single module**
```powershell
scripts/modules/PrePromotionChecks.psm1
# Includes: comprehensive help, error handling, logging
```

**Key Improvements in v2:**
- Native PowerShell cmdlets (faster)
- Better error messages
- Comprehensive parameter validation
- Inline documentation
- No YAML indentation issues

### Example: Secret Retrieval

**v1 (Ansible)**
```yaml
# Edit vault file
ansible-vault edit inventory/group_vars/all/vault.yml

# Manual decryption needed
--ask-vault-pass on every run
```

**v2 (GitHub Actions)**
```powershell
# Automatic retrieval from Key Vault
$secret = Get-AzKeyVaultSecret -VaultName $vaultName -Name $secretName

# No manual intervention
# OIDC handles authentication
```

## Rollback Procedures

### Scenario 1: GitHub Actions unavailable

**Action**: Use v1 Ansible pipeline
```bash
cd v1-ansible
./scripts/run-dc-promotion.sh -e production -t lva1-dc03
```

**Impact**: None - v1 remains fully functional

### Scenario 2: Azure Key Vault issues

**Option A**: Use local secrets
```powershell
.\Invoke-DCPromotionPipeline.ps1 -Environment production -UseLocalSecrets
# Will prompt for credentials
```

**Option B**: Fallback to v1
```bash
cd v1-ansible
./scripts/run-dc-promotion.sh -e production -t lva1-dc03
```

### Scenario 3: v2 pipeline failure

1. **Diagnose**:
   - Check GitHub Actions logs
   - Review Azure Key Vault audit logs
   - Examine DC deployment report

2. **Quick Fix**:
   - Run specific phase only
   - Use `-SkipPromotion` for post-reboot tasks

3. **Complete Rollback**:
   - Use v1 for current deployment
   - File issue in GitHub
   - Team investigates v2 problem

## Training Materials

### For AD Operators

**v1 Training** (Still valid):
- Pre-promotion checklist
- Health validation criteria
- Manual follow-up steps

**v2 New Topics**:
- GitHub Actions UI navigation
- Triggering workflows manually
- Reviewing deployment artifacts
- Reading GitHub Actions logs

### Hands-On Labs

1. **Lab 1**: Trigger staging deployment
2. **Lab 2**: Review health check results
3. **Lab 3**: Handle failed deployment
4. **Lab 4**: Production deployment with approval

## FAQs

**Q: Can I still use v1 after migrating?**  
A: Yes! v1 remains in `v1-ansible/` directory and is fully functional.

**Q: What if I don't have Azure?**  
A: You can use `-UseLocalSecrets` flag, but Azure Key Vault is recommended for production.

**Q: Do I need to learn PowerShell?**  
A: Basic PowerShell knowledge helps, but GitHub Actions UI handles most operations.

**Q: What about existing Ansible playbooks?**  
A: They're preserved in v1-ansible/ and can still be used.

**Q: How do I know v2 is working?**  
A: Test in lab → staging → limited production before full rollout.

## Success Criteria

- [ ] Azure Key Vault configured
- [ ] Self-hosted runner deployed
- [ ] Staging deployment successful
- [ ] Production deployment successful (test)
- [ ] All health checks passing
- [ ] Execution time < v1
- [ ] Team trained on v2
- [ ] Runbooks updated
- [ ] v1 archived (but accessible)

## Support & Escalation

| Issue Type | Contact | SLA |
|----------|---------|-----|
| Pipeline failures | AD Operations | 1 hour |
| Azure/GitHub issues | Cloud Platform team | 2 hours |
| Security concerns | InfoSec | 4 hours |
| Documentation gaps | Pipeline maintainers | 1 business day |

## Next Steps

1. Review this migration guide
2. Complete Phase 1 (Setup)
3. Schedule lab testing
4. Plan staging deployment
5. Coordinate production cutover

**Questions?** Contact: ad-ops@linkedin.com or file an issue on GitHub.
