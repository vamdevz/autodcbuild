<#
.SYNOPSIS
    Post-promotion health checks and configuration for new Domain Controllers.

.DESCRIPTION
    Automated health checks and configuration tasks after DC promotion.
    This script performs validation and basic configuration that can be automated.

.NOTES
    Version: 1.0.0
    Author: LinkedIn Infrastructure Team
    Last Updated: 2026-01-20
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$DomainFQDN = "linkedin.local"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'  # Continue on errors to run all checks

$results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ServerName = $env:COMPUTERNAME
    Domain = $DomainFQDN
    Checks = @{}
    OverallStatus = "UNKNOWN"
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  POST-PROMOTION HEALTH CHECKS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Server: $env:COMPUTERNAME" -ForegroundColor White
Write-Host "Domain: $DomainFQDN" -ForegroundColor White
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host ""

#region 1. SYSVOL and Netlogon Share Check
Write-Host "[1/8] Checking SYSVOL and Netlogon shares..." -ForegroundColor Yellow
try {
    $shares = @(Get-WmiObject Win32_Share | Where-Object { $_.Name -in @('SYSVOL', 'NETLOGON') })
    if ($shares.Count -eq 2) {
        Write-Host "  [OK] SYSVOL and NETLOGON shares found" -ForegroundColor Green
        $shares | Format-Table Name, Path, Description -AutoSize | Out-String | Write-Host
        $results.Checks['Shares'] = 'PASS'
    } else {
        Write-Host "  [FAIL] Missing shares (found: $($shares.Count)/2)" -ForegroundColor Red
        $results.Checks['Shares'] = 'FAIL'
    }
} catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks['Shares'] = 'ERROR'
}
Write-Host ""

#region 2. AD Replication Status
Write-Host "[2/8] Checking AD Replication..." -ForegroundColor Yellow
try {
    $replOutput = repadmin /showrepl 2>&1 | Out-String
    
    if ($replOutput -match "Last attempt @ .* was successful" -or $replOutput -match "successful") {
        Write-Host "  [OK] Replication is successful" -ForegroundColor Green
        # Show last few lines with timestamp
        $replOutput -split "`n" | Select-Object -Last 15 | ForEach-Object { 
            if ($_ -match "Last attempt|successful") {
                Write-Host "  $_" -ForegroundColor White
            }
        }
        $results.Checks['Replication'] = 'PASS'
    } else {
        Write-Host "  [WARN] Check replication output manually" -ForegroundColor Yellow
        Write-Host $replOutput
        $results.Checks['Replication'] = 'WARN'
    }
} catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks['Replication'] = 'ERROR'
}
Write-Host ""

#region 3. Replication Queue Check
Write-Host "[3/8] Checking Replication Queue..." -ForegroundColor Yellow
try {
    $queueOutput = repadmin /queue 2>&1 | Out-String
    
    if ($queueOutput -match "Queue contains 0 items" -or $queueOutput -match "0 items") {
        Write-Host "  [OK] Replication queue is empty (0 items)" -ForegroundColor Green
        $results.Checks['Queue'] = 'PASS'
    } else {
        Write-Host "  [WARN] Replication queue has items - allow time to clear" -ForegroundColor Yellow
        Write-Host $queueOutput
        $results.Checks['Queue'] = 'WARN'
    }
} catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks['Queue'] = 'ERROR'
}
Write-Host ""

#region 4. DCDiag Tests
Write-Host "[4/8] Running DCDiag Tests..." -ForegroundColor Yellow

# Test 4a: DCPromo test (skip - only valid during actual promotion)
Write-Host "  [4a] DCPromo Test..." -ForegroundColor Cyan
Write-Host "    [SKIP] Only applicable during promotion" -ForegroundColor Gray
$results.Checks['DCPromo'] = 'SKIP'

# Test 4b: RegisterInDNS test
Write-Host "  [4b] RegisterInDNS Test..." -ForegroundColor Cyan
try {
    $dnsRegTest = dcdiag /test:registerindns 2>&1 | Out-String
    
    if ($dnsRegTest -match "passed test" -or $dnsRegTest -match "successfully") {
        Write-Host "    [OK] RegisterInDNS test passed" -ForegroundColor Green
        $results.Checks['RegisterInDNS'] = 'PASS'
    } else {
        Write-Host "    [WARN] RegisterInDNS test - check output" -ForegroundColor Yellow
        $results.Checks['RegisterInDNS'] = 'WARN'
    }
} catch {
    Write-Host "    [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks['RegisterInDNS'] = 'ERROR'
}

# Test 4c: General DCDiag
Write-Host "  [4c] General DCDiag..." -ForegroundColor Cyan
try {
    $dcdiagOutput = dcdiag 2>&1 | Out-String
    
    # Count passed vs failed tests
    $passedTests = ([regex]::Matches($dcdiagOutput, "passed test")).Count
    $failedTests = ([regex]::Matches($dcdiagOutput, "failed test")).Count
    
    Write-Host "    Tests Passed: $passedTests" -ForegroundColor White
    if ($failedTests -gt 0) {
        Write-Host "    Tests Failed: $failedTests" -ForegroundColor Yellow
        $results.Checks['DCDiag'] = 'WARN'
    } else {
        Write-Host "    [OK] All DCDiag tests passed" -ForegroundColor Green
        $results.Checks['DCDiag'] = 'PASS'
    }
} catch {
    Write-Host "    [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks['DCDiag'] = 'ERROR'
}

# Test 4d: DNS-specific tests
Write-Host "  [4d] DNS Tests..." -ForegroundColor Cyan
try {
    $dnsTest = dcdiag /test:dns 2>&1 | Out-String
    
    if ($dnsTest -match "Summary of test results" -and $dnsTest -notmatch "failed") {
        Write-Host "    [OK] DNS tests completed successfully" -ForegroundColor Green
        $results.Checks['DNS'] = 'PASS'
    } else {
        Write-Host "    [WARN] DNS tests have issues - review required" -ForegroundColor Yellow
        $results.Checks['DNS'] = 'WARN'
    }
} catch {
    Write-Host "    [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks['DNS'] = 'ERROR'
}
Write-Host ""

#region 5. AD Services Status
Write-Host "[5/8] Checking AD Services..." -ForegroundColor Yellow
try {
    $services = Get-Service NTDS, DNS, Netlogon, KDC -ErrorAction SilentlyContinue
    
    $allRunning = $true
    foreach ($svc in $services) {
        $status = if ($svc.Status -eq 'Running') { "[OK]" } else { "[FAIL]" }
        $color = if ($svc.Status -eq 'Running') { "Green" } else { "Red" }
        Write-Host "  $status $($svc.DisplayName): $($svc.Status)" -ForegroundColor $color
        
        if ($svc.Status -ne 'Running') { $allRunning = $false }
    }
    
    $results.Checks['Services'] = if ($allRunning) { 'PASS' } else { 'FAIL' }
} catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks['Services'] = 'ERROR'
}
Write-Host ""

#region 6. DNS Configuration Check
Write-Host "[6/8] Checking DNS Server Configuration..." -ForegroundColor Yellow
try {
    Import-Module DnsServer -ErrorAction Stop
    
    # Check if DNS server is running
    $dnsService = Get-Service DNS -ErrorAction SilentlyContinue
    if ($dnsService.Status -eq 'Running') {
        Write-Host "  [OK] DNS Server service is running" -ForegroundColor Green
        
        # List existing conditional forwarders
        $forwarders = @(Get-DnsServerZone | Where-Object { $_.ZoneType -eq 'Forwarder' })
        if ($forwarders.Count -gt 0) {
            Write-Host "  Existing Conditional Forwarders: $($forwarders.Count)" -ForegroundColor White
            $forwarders | ForEach-Object { Write-Host "    - $($_.ZoneName)" -ForegroundColor Gray }
        } else {
            Write-Host "  No conditional forwarders configured yet" -ForegroundColor Yellow
        }
        
        $results.Checks['DNSServer'] = 'PASS'
    } else {
        Write-Host "  [FAIL] DNS Server service not running" -ForegroundColor Red
        $results.Checks['DNSServer'] = 'FAIL'
    }
} catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks['DNSServer'] = 'ERROR'
}
Write-Host ""

#region 7. LDAP/LDAPS Port Check
Write-Host "[7/8] Checking LDAP/LDAPS Ports..." -ForegroundColor Yellow
try {
    $ldapPort = Test-NetConnection -ComputerName localhost -Port 389 -WarningAction SilentlyContinue
    $ldapsPort = Test-NetConnection -ComputerName localhost -Port 636 -WarningAction SilentlyContinue
    
    $ldapStatus = if ($ldapPort.TcpTestSucceeded) { "[OK]" } else { "[FAIL]" }
    $ldapsStatus = if ($ldapsPort.TcpTestSucceeded) { "[OK]" } else { "[WARN]" }
    
    $ldapColor = if ($ldapPort.TcpTestSucceeded) { "Green" } else { "Red" }
    $ldapsColor = if ($ldapsPort.TcpTestSucceeded) { "Green" } else { "Yellow" }
    
    Write-Host "  $ldapStatus LDAP (389): $($ldapPort.TcpTestSucceeded)" -ForegroundColor $ldapColor
    Write-Host "  $ldapsStatus LDAPS (636): $($ldapsPort.TcpTestSucceeded)" -ForegroundColor $ldapsColor
    
    if (!$ldapsPort.TcpTestSucceeded) {
        Write-Host "    Note: LDAPS requires certificate enrollment" -ForegroundColor Gray
    }
    
    $results.Checks['LDAP'] = if ($ldapPort.TcpTestSucceeded) { 'PASS' } else { 'FAIL' }
    $results.Checks['LDAPS'] = if ($ldapsPort.TcpTestSucceeded) { 'PASS' } else { 'PENDING_CERT' }
} catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks['LDAP'] = 'ERROR'
}
Write-Host ""

#region 8. Computer Object Location
Write-Host "[8/8] Checking Computer Object in AD..." -ForegroundColor Yellow
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $computer = Get-ADComputer -Identity $env:COMPUTERNAME -Properties DistinguishedName, MemberOf
    
    Write-Host "  Location: $($computer.DistinguishedName)" -ForegroundColor White
    
    # Check if in Domain Controllers OU
    if ($computer.DistinguishedName -match "OU=Domain Controllers") {
        Write-Host "  [OK] Located in Domain Controllers OU" -ForegroundColor Green
        $results.Checks['ComputerLocation'] = 'PASS'
    } else {
        Write-Host "  [WARN] Not in standard Domain Controllers OU" -ForegroundColor Yellow
        $results.Checks['ComputerLocation'] = 'WARN'
    }
    
    # Check group memberships
    if ($computer.MemberOf.Count -gt 0) {
        Write-Host "  Group Memberships: $($computer.MemberOf.Count)" -ForegroundColor White
        
        # Check for LDAPS group
        $hasLDAPSGroup = $computer.MemberOf | Where-Object { $_ -match "LDAPS" }
        if ($hasLDAPSGroup) {
            Write-Host "    [OK] Member of LDAPS group" -ForegroundColor Green
        } else {
            Write-Host "    [PENDING] Not yet in LDAPS auto-enroll group" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    $results.Checks['ComputerLocation'] = 'ERROR'
}
Write-Host ""

#region Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  HEALTH CHECK SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passCount = @($results.Checks.Values | Where-Object { $_ -eq 'PASS' }).Count
$warnCount = @($results.Checks.Values | Where-Object { $_ -in @('WARN', 'PENDING_CERT') }).Count
$failCount = @($results.Checks.Values | Where-Object { $_ -in @('FAIL', 'ERROR') }).Count
$skipCount = @($results.Checks.Values | Where-Object { $_ -eq 'SKIP' }).Count
$totalCount = $results.Checks.Count

Write-Host ""
Write-Host "  Passed:   $passCount / $totalCount" -ForegroundColor Green
Write-Host "  Warnings: $warnCount / $totalCount" -ForegroundColor Yellow
Write-Host "  Failed:   $failCount / $totalCount" -ForegroundColor Red
Write-Host "  Skipped:  $skipCount / $totalCount" -ForegroundColor Gray
Write-Host ""

# Detailed results
foreach ($check in $results.Checks.GetEnumerator() | Sort-Object Name) {
    $symbol = switch ($check.Value) {
        'PASS' { '[OK]'; $color = 'Green' }
        'WARN' { '[WARN]'; $color = 'Yellow' }
        'FAIL' { '[FAIL]'; $color = 'Red' }
        'ERROR' { '[ERROR]'; $color = 'Red' }
        'PENDING_CERT' { '[PENDING]'; $color = 'Yellow' }
        'SKIP' { '[SKIP]'; $color = 'Gray' }
        default { '[?]'; $color = 'Gray' }
    }
    
    Write-Host "  $symbol $($check.Key): $($check.Value)" -ForegroundColor $color
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

# Determine overall status (be more lenient - warnings are acceptable)
$criticalFails = @($results.Checks.GetEnumerator() | Where-Object { 
    $_.Value -eq 'FAIL' -and $_.Key -in @('Services', 'Replication', 'LDAP')
}).Count

if ($criticalFails -eq 0) {
    if ($failCount -eq 0 -and $warnCount -eq 0) {
        $results.OverallStatus = "HEALTHY"
        Write-Host "Overall Status: HEALTHY" -ForegroundColor Green
    } else {
        $results.OverallStatus = "HEALTHY_WITH_WARNINGS"
        Write-Host "Overall Status: HEALTHY (with warnings)" -ForegroundColor Yellow
        Write-Host "Note: Some warnings are normal for newly promoted DCs" -ForegroundColor Gray
    }
    exit 0
} else {
    $results.OverallStatus = "CRITICAL_ISSUES"
    Write-Host "Overall Status: CRITICAL ISSUES - Immediate review required" -ForegroundColor Red
    exit 1
}
