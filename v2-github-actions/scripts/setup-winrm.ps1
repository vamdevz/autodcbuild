<#
.SYNOPSIS
    Configure WinRM for remote PowerShell access from GitHub Actions runners.

.DESCRIPTION
    Enables WinRM HTTP (port 5985) with Basic authentication for use with
    GitHub Actions workflows. This script is executed via Azure VM Custom Script Extension
    during VM creation.

.NOTES
    Version: 1.0.0
    Author: LinkedIn Infrastructure Team
    Last Updated: 2026-01-20

    WARNING: This configuration allows unencrypted HTTP traffic and Basic auth.
    Only use in isolated lab/test environments with proper network security groups.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Configuring WinRM for Remote Access" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Enable PowerShell Remoting
    Write-Host "[1/5] Enabling PowerShell Remoting..." -ForegroundColor Yellow
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Write-Host "OK: PowerShell Remoting enabled" -ForegroundColor Green

    # Configure WinRM Service
    Write-Host "[2/5] Configuring WinRM Service..." -ForegroundColor Yellow
    Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
    Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
    Set-Item WSMan:\localhost\MaxTimeoutms -Value 1800000
    Write-Host "OK: WinRM Service configured" -ForegroundColor Green

    # Create Firewall Rule
    Write-Host "[3/5] Creating Firewall Rule..." -ForegroundColor Yellow
    $firewallRule = Get-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -ErrorAction SilentlyContinue
    if (-not $firewallRule) {
        New-NetFirewallRule -Name "WinRM-HTTP-In-TCP" `
            -DisplayName "Windows Remote Management (HTTP-In)" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 5985 `
            -Profile Any
        Write-Host "OK: Firewall rule created" -ForegroundColor Green
    } else {
        Write-Host "OK: Firewall rule already exists" -ForegroundColor Green
    }

    # Restart WinRM Service
    Write-Host "[4/5] Restarting WinRM Service..." -ForegroundColor Yellow
    Restart-Service WinRM -Force
    Write-Host "OK: WinRM Service restarted" -ForegroundColor Green

    # Verify Configuration
    Write-Host "[5/5] Verifying Configuration..." -ForegroundColor Yellow
    $winrmStatus = Get-Service WinRM
    $listener = Get-WSManInstance -ResourceURI winrm/config/listener -SelectorSet @{Address="*";Transport="HTTP"}

    if ($winrmStatus.Status -eq 'Running' -and $listener) {
        Write-Host "OK: WinRM is running and configured" -ForegroundColor Green
        Write-Host ""
        Write-Host "Listener Details:" -ForegroundColor Cyan
        Write-Host "  Address: $($listener.Address)" -ForegroundColor White
        Write-Host "  Port: $($listener.Port)" -ForegroundColor White
        Write-Host "  Transport: $($listener.Transport)" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  OK: WinRM Configuration Complete" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""

    exit 0

} catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ERROR: WinRM Configuration Failed" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host ("Error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ""
    exit 1
}
