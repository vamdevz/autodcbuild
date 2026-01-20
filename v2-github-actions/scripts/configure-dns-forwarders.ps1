<#
.SYNOPSIS
    Configure DNS Conditional Forwarders for linkedin.biz environment.

.DESCRIPTION
    Adds required conditional forwarders for cross-domain resolution and Microsoft services.
    
.PARAMETER DomainType
    Specify 'biz' for linkedin.biz DCs or 'china' for internal.linkedin.cn DCs.

.NOTES
    Version: 1.0.0
    Author: LinkedIn Infrastructure Team
    Last Updated: 2026-01-20
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('biz', 'china', 'local')]
    [string]$DomainType = "local"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DNS CONDITIONAL FORWARDER SETUP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Domain Type: $DomainType" -ForegroundColor White
Write-Host "Server: $env:COMPUTERNAME" -ForegroundColor White
Write-Host ""

# Import DNS Server module
try {
    Import-Module DnsServer -ErrorAction Stop
    Write-Host "[OK] DNS Server module loaded" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to load DNS Server module: $_" -ForegroundColor Red
    exit 1
}

# Define forwarder configurations
$forwarders = @()

# Microsoft GTM and STS forwarders (required for all)
$forwarders += @{
    ZoneName = "gtm.corp.microsoft.com"
    MasterServers = @("172.31.197.245", "172.31.197.246", "172.31.197.80", "172.31.197.81")
    Description = "Microsoft GTM Services"
}

$forwarders += @{
    ZoneName = "sts.microsoft.com"
    MasterServers = @("172.31.197.245", "172.31.197.246", "172.31.197.80", "172.31.197.81")
    Description = "Microsoft STS Services"
}

# Domain-specific forwarders
if ($DomainType -eq 'biz') {
    # Add China domain forwarder when in BIZ
    $forwarders += @{
        ZoneName = "internal.linkedin.cn"
        MasterServers = @("10.44.71.6", "10.44.71.5")
        Description = "LinkedIn China Domain"
    }
    Write-Host "[INFO] Added China domain forwarder (for BIZ domain DCs)" -ForegroundColor Cyan
    
} elseif ($DomainType -eq 'china') {
    # Add BIZ domain forwarder when in China
    $forwarders += @{
        ZoneName = "linkedin.biz"
        MasterServers = @("10.41.63.5", "10.41.63.6", "172.21.2.103", "172.21.2.104")
        Description = "LinkedIn BIZ Domain"
    }
    Write-Host "[INFO] Added BIZ domain forwarder (for China domain DCs)" -ForegroundColor Cyan
    
} elseif ($DomainType -eq 'local') {
    Write-Host "[INFO] Lab/Local domain - skipping cross-domain forwarders" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Configuring $($forwarders.Count) conditional forwarders..." -ForegroundColor Yellow
Write-Host ""

$successCount = 0
$skipCount = 0
$errorCount = 0

foreach ($fwd in $forwarders) {
    Write-Host "Processing: $($fwd.ZoneName)..." -ForegroundColor Cyan
    
    try {
        # Check if forwarder already exists
        $existing = Get-DnsServerZone -Name $fwd.ZoneName -ErrorAction SilentlyContinue
        
        if ($existing) {
            Write-Host "  [SKIP] Forwarder already exists" -ForegroundColor Yellow
            $skipCount++
        } else {
            # Add conditional forwarder
            Add-DnsServerConditionalForwarderZone `
                -Name $fwd.ZoneName `
                -MasterServers $fwd.MasterServers `
                -ErrorAction Stop
            
            Write-Host "  [OK] Created successfully" -ForegroundColor Green
            Write-Host "    Master Servers: $($fwd.MasterServers -join ', ')" -ForegroundColor Gray
            $successCount++
        }
    } catch {
        Write-Host "  [ERROR] Failed: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
    
    Write-Host ""
}

# Test DNS resolution
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TESTING DNS RESOLUTION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Test domains based on configuration
$testDomains = @("sts.microsoft.com", "gtm.corp.microsoft.com")

if ($DomainType -eq 'biz') {
    $testDomains += "internal.linkedin.cn"
} elseif ($DomainType -eq 'china') {
    $testDomains += "linkedin.biz"
}

foreach ($domain in $testDomains) {
    Write-Host "Testing: $domain" -ForegroundColor Cyan
    try {
        $result = Resolve-DnsName $domain -Type A -ErrorAction Stop | Select-Object -First 1
        Write-Host "  [OK] Resolved to: $($result.IPAddress)" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Resolution failed (may need time to propagate)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Created: $successCount" -ForegroundColor Green
Write-Host "  Skipped: $skipCount" -ForegroundColor Yellow
Write-Host "  Errors:  $errorCount" -ForegroundColor Red
Write-Host ""

if ($errorCount -eq 0) {
    Write-Host "DNS Conditional Forwarders configured successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "DNS Configuration completed with errors" -ForegroundColor Yellow
    exit 1
}
