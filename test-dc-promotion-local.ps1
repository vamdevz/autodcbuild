# Quick Test Script for DC Promotion Pipeline
# Run this from your local machine (Mac/Windows/Linux with PowerShell)

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  DC Promotion Pipeline - Local Test" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# Configuration
$TargetDC = "4.234.159.63"
$DomainUser = "linkedin\vamdev"
$DomainPass = "Sarita123@@@"
$SafeModePass = "Sarita123@@@"

# Test connectivity first
Write-Host "1. Testing connectivity to DC01..." -ForegroundColor Yellow
$testResult = Test-NetConnection -ComputerName $TargetDC -Port 5985 -WarningAction SilentlyContinue

if ($testResult.TcpTestSucceeded) {
    Write-Host "   ✅ WinRM port 5985 is accessible" -ForegroundColor Green
} else {
    Write-Host "   ❌ Cannot reach WinRM port 5985" -ForegroundColor Red
    Write-Host "   Check that DC01 is running and NSG allows port 5985" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "2. Setting up credentials..." -ForegroundColor Yellow
$SecurePassword = ConvertTo-SecureString $DomainPass -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($DomainUser, $SecurePassword)
Write-Host "   ✅ Credentials configured" -ForegroundColor Green

Write-Host ""
Write-Host "3. Testing WinRM connection..." -ForegroundColor Yellow
try {
    $testSession = Test-WSMan -ComputerName $TargetDC -Credential $Credential -ErrorAction Stop
    Write-Host "   ✅ WinRM connection successful" -ForegroundColor Green
} catch {
    Write-Host "   ❌ WinRM authentication failed" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Possible issues:" -ForegroundColor Yellow
    Write-Host "   - Wrong credentials" -ForegroundColor Yellow
    Write-Host "   - WinRM not properly configured on DC01" -ForegroundColor Yellow
    Write-Host "   - TrustedHosts not configured" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Try adding DC01 to TrustedHosts:" -ForegroundColor Cyan
    Write-Host "   Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$TargetDC' -Force" -ForegroundColor White
    exit 1
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  ✅ All Pre-Tests Passed!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ready to run DC promotion pipeline!" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Navigate to scripts directory:" -ForegroundColor White
Write-Host "   cd v2-github-actions/scripts" -ForegroundColor Yellow
Write-Host ""
Write-Host "2. Import modules:" -ForegroundColor White
Write-Host "   Import-Module .\modules\PrePromotionChecks.psm1" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. Run pre-checks:" -ForegroundColor White
Write-Host "   `$cred = Get-Credential  # Use: linkedin\vamdev" -ForegroundColor Yellow
Write-Host "   Invoke-AllPreChecks -TargetDC '$TargetDC' -Credential `$cred" -ForegroundColor Yellow
Write-Host ""
Write-Host "4. Or run full pipeline:" -ForegroundColor White
Write-Host "   Set environment variables:" -ForegroundColor Yellow
Write-Host "   `$env:DOMAIN_ADMIN_USER = '$DomainUser'" -ForegroundColor Yellow
Write-Host "   `$env:DOMAIN_ADMIN_PASS = '$DomainPass'" -ForegroundColor Yellow
Write-Host "   `$env:SAFE_MODE_PASS = '$SafeModePass'" -ForegroundColor Yellow
Write-Host ""
Write-Host "   Then run:" -ForegroundColor Yellow
Write-Host "   .\Invoke-DCPromotionPipeline.ps1 ``" -ForegroundColor Yellow
Write-Host "     -Environment lab ``" -ForegroundColor Yellow
Write-Host "     -TargetDC '$TargetDC' ``" -ForegroundColor Yellow
Write-Host "     -UseLocalSecrets ``" -ForegroundColor Yellow
Write-Host "     -Verbose" -ForegroundColor Yellow
Write-Host ""
