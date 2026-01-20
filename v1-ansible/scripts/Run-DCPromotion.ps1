#!/usr/bin/env pwsh
# scripts/Run-DCPromotion.ps1
# PowerShell wrapper for DC promotion pipeline

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Staging', 'Production')]
    [string]$Environment,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetHost,
    
    [Parameter(Mandatory=$false)]
    [switch]$CheckMode,
    
    [Parameter(Mandatory=$false)]
    [string]$VaultPasswordFile
)

$ErrorActionPreference = "Stop"

# Colors
function Write-ColorOutput {
    param(
        [string]$Message,
        [ValidateSet('Green', 'Yellow', 'Red', 'White')]
        [string]$Color = 'White'
    )
    
    $colorMap = @{
        'Green' = [ConsoleColor]::Green
        'Yellow' = [ConsoleColor]::Yellow
        'Red' = [ConsoleColor]::Red
        'White' = [ConsoleColor]::White
    }
    
    Write-Host $Message -ForegroundColor $colorMap[$Color]
}

# Get project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Validate environment
$envLower = $Environment.ToLower()
if ($envLower -notin @('staging', 'production')) {
    Write-ColorOutput "ERROR: Environment must be 'Staging' or 'Production'" -Color Red
    exit 1
}

# Production confirmation
if ($envLower -eq 'production' -and -not $CheckMode) {
    Write-ColorOutput "`n⚠️  WARNING: You are about to promote a PRODUCTION domain controller!" -Color Yellow
    Write-ColorOutput "Target: $TargetHost" -Color Yellow
    Write-Host ""
    
    $confirmation = Read-Host "Type 'PROMOTE' to continue"
    if ($confirmation -ne 'PROMOTE') {
        Write-ColorOutput "Aborted by user" -Color Red
        exit 1
    }
}

# Build ansible-playbook command
Set-Location $ProjectRoot

$ansibleCmd = @(
    'ansible-playbook',
    'playbooks/master-pipeline.yml',
    '-i', "inventory/$envLower/hosts.yml",
    '--limit', $TargetHost
)

if ($CheckMode) {
    $ansibleCmd += '--check'
    Write-ColorOutput "Running in CHECK MODE (dry-run)" -Color Yellow
}

if ($VaultPasswordFile) {
    $ansibleCmd += '--vault-password-file', $VaultPasswordFile
} else {
    $ansibleCmd += '--ask-vault-pass'
}

# Display execution plan
Write-Host ""
Write-ColorOutput "============================================" -Color Green
Write-ColorOutput "DC PROMOTION PIPELINE" -Color Green
Write-ColorOutput "============================================" -Color Green
Write-Host "Environment: $Environment"
Write-Host "Target Host: $TargetHost"
Write-Host "Check Mode: $CheckMode"
Write-Host "Project Root: $ProjectRoot"
Write-Host ""
Write-ColorOutput "Executing: $($ansibleCmd -join ' ')" -Color Green
Write-Host ""

# Execute playbook
$process = Start-Process -FilePath 'ansible-playbook' -ArgumentList ($ansibleCmd[1..($ansibleCmd.Length-1)]) -NoNewWindow -Wait -PassThru

# Completion message
if ($process.ExitCode -eq 0) {
    Write-Host ""
    Write-ColorOutput "============================================" -Color Green
    Write-ColorOutput "✅ DEPLOYMENT COMPLETE" -Color Green
    Write-ColorOutput "============================================" -Color Green
    Write-Host "Server: $TargetHost"
    Write-Host "Environment: $Environment"
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "1. Verify certificate: go/incerts"
    Write-Host "2. Confirm FIM compliance with InfoSec SPM team"
    Write-Host "3. Update change ticket"
    Write-Host "4. Monitor agent initialization (5-10 minutes)"
    Write-Host ""
} else {
    Write-Host ""
    Write-ColorOutput "============================================" -Color Red
    Write-ColorOutput "❌ DEPLOYMENT FAILED" -Color Red
    Write-ColorOutput "============================================" -Color Red
    Write-Host "Check logs above for errors"
    exit 1
}
