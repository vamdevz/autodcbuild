# DC Deployment Report

**DC Name**: `FreshDC1446`  
**Domain**: `linkedin.local`  
**IP Address**: `51.11.191.128`  
**Deployment Date**: 2026-01-20 17:47:32 UTC  
**Pipeline Run**: [View Logs](https://github.com/vamdevz/autodcbuild/actions/runs/21181490484)  
**Status**: ✅ **Successfully Deployed**

---

## 📋 Deployment Summary

| Phase | Status | Duration |
|-------|--------|----------|
| VM Provisioning | ✅ Complete | ~2-3 min |
| DC Promotion | ✅ Complete | ~4-5 min |
| Health Validation | ✅ Complete | ~1-2 min |
| **Total** | ✅ **Success** | **~7 min** |

---

## 🖥️ VM Configuration

| Property | Value |
|----------|-------|
| Computer Name | FreshDC1446 |
| Domain | linkedin.local |
| Operating System | Windows Server 2019 Datacenter |
| Azure Resource Group | VAMDEVTEST |
| Azure Region | UK South |
| Public IP | 51.11.191.128 |

---

## 🔧 Active Directory Services

| Service | Status |
|---------|--------|
| Active Directory Domain Services (NTDS) | ✅ Running |
| DNS Server | ✅ Running |
| Netlogon | ✅ Running |
| Kerberos Key Distribution Center (KDC) | ✅ Running |

**Result**: ✅ All critical AD services are running

---

## 🔄 AD Replication Status

### Replication Summary

```
Last attempt @ 2026-01-20 17:45:12 was successful.
Last attempt @ 2026-01-20 17:45:18 was successful.
```

**Status**: ✅ Replication is working  
**Replication Queue**: ✅ Empty (0 items)  
**Last Check**: Successful

---

## 🏥 DCDiag Health Checks

### Test Results Summary

**Tests Passed**: 24  
**Tests Failed**: 4  
**Status**: ⚠️ 4 tests failed (non-critical)

### Connectivity Tests

| Protocol | Port | Status |
|----------|------|--------|
| LDAP | 389 | ✅ Accessible |
| LDAPS | 636 | ✅ Accessible |

---

## 🌐 DNS Configuration

### DNS Forwarders

| Zone Name | Type |
|-----------|------|
| gtm.corp.microsoft.com | Conditional Forwarder |
| sts.microsoft.com | Conditional Forwarder |

**Status**: ✅ DNS forwarders configured successfully

---

## ✅ Deployment Verification

### Health Status Overview

| Component | Status |
|-----------|--------|
| DC Promotion | ✅ Successful |
| Service Status | ✅ All Running |
| AD Replication | ✅ Working |
| DNS Configuration | ✅ Configured |
| LDAP Connectivity | ✅ Accessible |

**Overall Status**: ✅ **Healthy - Ready for Use**

---

## 📊 Quick Verification

To verify the DC manually, run these commands:

```powershell
# Check all services
Get-Service NTDS,DNS,Netlogon,KDC | Format-Table Status,Name

# Verify replication
repadmin /showrepl

# Run health check
dcdiag /v

# Test DNS
nslookup $(hostname)
```

---

## 🔗 Additional Resources

- **Workflow Run**: [View Full Logs](https://github.com/vamdevz/autodcbuild/actions/runs/21181490484)
- **Repository**: [GitHub Repository](https://github.com/vamdevz/autodcbuild)
- **Documentation**: See `POST-PROMOTION-TASKS.md` for additional configuration

---

*Report generated automatically by DC Build Pipeline v2.0*  
*Timestamp: 2026-01-20 17:47:32 UTC*
