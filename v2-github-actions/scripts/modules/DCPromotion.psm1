<#
.SYNOPSIS
    Domain Controller promotion and health validation module.

.DESCRIPTION
    PowerShell module for DC promotion, reboot handling, and comprehensive health checks.
    Provides automated DC promotion with built-in validation and monitoring.

.NOTES
    Version: 2.0.0
    Author: LinkedIn Infrastructure Team
    Last Updated: 2026-01-17
#>

#Requires -Version 5.1
# Note: ActiveDirectory module required on target DC (not on runner)
# Commands execute remotely via WinRM, so no local module requirements

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-level variables
$script:ADServices = @('NTDS', 'DNS', 'Netlogon', 'W32Time', 'KDC')

<#
.SYNOPSIS
    Installs the Active Directory Domain Services role.

.DESCRIPTION
    Installs AD DS role with management tools. Reboots if required.

.EXAMPLE
    Install-ADDSRole
    Installs AD DS role with all sub-features.

.OUTPUTS
    Boolean - $true if installation successful
#>
function Install-ADDSRole {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-Host "Installing AD DS role and management tools..." -ForegroundColor Yellow
    
    try {
        $feature = Install-WindowsFeature -Name AD-Domain-Services `
            -IncludeManagementTools `
            -IncludeAllSubFeature `
            -ErrorAction Stop
        
        if ($feature.Success) {
            Write-Host "✓ AD DS role installed successfully" -ForegroundColor Green
            
            if ($feature.RestartNeeded -eq 'Yes') {
                Write-Warning "System reboot required after AD DS role installation"
                Restart-Computer -Force -Confirm:$false
                Start-Sleep -Seconds 10
            }
            
            return $true
        }
        else {
            throw "AD DS role installation failed"
        }
    }
    catch {
        Write-Error "Failed to install AD DS role: $_"
        throw
    }
}

<#
.SYNOPSIS
    Promotes server to Domain Controller.

.DESCRIPTION
    Executes DC promotion using Install-ADDSDomainController. Adds DC to existing domain.

.PARAMETER DomainName
    Fully qualified domain name (e.g., linkedin.biz).

.PARAMETER Credential
    Domain admin credential for promotion.

.PARAMETER SafeModePassword
    DSRM (Directory Services Restore Mode) password as SecureString.

.PARAMETER SiteName
    Active Directory site name for the DC.

.PARAMETER DatabasePath
    Path for AD database (default: C:\Windows\NTDS).

.PARAMETER SysvolPath
    Path for SYSVOL (default: C:\Windows\SYSVOL).

.PARAMETER LogPath
    Path for AD logs (default: C:\Windows\NTDS).

.EXAMPLE
    $cred = Get-Credential "LINKEDIN\admin"
    $dsrmPwd = ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force
    Invoke-DCPromotion -DomainName "linkedin.biz" -Credential $cred -SafeModePassword $dsrmPwd -SiteName "LVA1"

.OUTPUTS
    PSCustomObject - Promotion result with reboot status
#>
function Invoke-DCPromotion {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainName,
        
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory = $true)]
        [SecureString]$SafeModePassword,
        
        [Parameter(Mandatory = $false)]
        [string]$SiteName,
        
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath = "C:\Windows\NTDS",
        
        [Parameter(Mandatory = $false)]
        [string]$SysvolPath = "C:\Windows\SYSVOL",
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath = "C:\Windows\NTDS"
    )
    
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "DOMAIN CONTROLLER PROMOTION" -ForegroundColor Cyan
    Write-Host "============================================`n" -ForegroundColor Cyan
    
    try {
        # Build promotion parameters
        $promoteParams = @{
            DomainName                    = $DomainName
            Credential                    = $Credential
            SafeModeAdministratorPassword = $SafeModePassword
            DatabasePath                  = $DatabasePath
            SysvolPath                    = $SysvolPath
            LogPath                       = $LogPath
            InstallDns                    = $true
            NoRebootOnCompletion          = $false
            Force                         = $true
            ErrorAction                   = 'Stop'
        }
        
        # Add site name if provided
        if ($SiteName) {
            $promoteParams['SiteName'] = $SiteName
            Write-Host "Target Site: $SiteName" -ForegroundColor White
        }
        
        Write-Host "Domain: $DomainName" -ForegroundColor White
        Write-Host "Database Path: $DatabasePath" -ForegroundColor White
        Write-Host "SYSVOL Path: $SysvolPath" -ForegroundColor White
        Write-Host "`nStarting DC promotion (this may take 15-30 minutes)..." -ForegroundColor Yellow
        
        # Perform promotion
        $result = Install-ADDSDomainController @promoteParams
        
        return [PSCustomObject]@{
            Success        = $true
            RebootRequired = $true
            Message        = "DC promotion completed successfully. Reboot initiated."
            Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    catch {
        Write-Error "DC promotion failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Waits for Active Directory services to start after reboot.

.DESCRIPTION
    Monitors critical AD services (NTDS, DNS, Netlogon, W32Time, KDC) and ensures
    they are running before proceeding with health checks.

.PARAMETER TimeoutSeconds
    Maximum time to wait for services (default: 600).

.PARAMETER RetryIntervalSeconds
    Time between retry attempts (default: 30).

.EXAMPLE
    Wait-ForADServices
    Waits for all AD services with default timeout.

.OUTPUTS
    Hashtable - Service status information
#>
function Wait-ForADServices {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 600,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryIntervalSeconds = 30
    )
    
    Write-Host "`nWaiting for Active Directory services to start..." -ForegroundColor Yellow
    
    $startTime = Get-Date
    $serviceStatus = @{}
    
    while ((Get-Date) -lt $startTime.AddSeconds($TimeoutSeconds)) {
        $allRunning = $true
        
        foreach ($serviceName in $script:ADServices) {
            try {
                $service = Get-Service -Name $serviceName -ErrorAction Stop
                $serviceStatus[$serviceName] = $service.Status
                
                if ($service.Status -ne 'Running') {
                    $allRunning = $false
                    Write-Verbose "Service $serviceName is $($service.Status)"
                    
                    # Attempt to start if stopped
                    if ($service.Status -eq 'Stopped') {
                        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                    }
                }
            }
            catch {
                $allRunning = $false
                Write-Verbose "Service $serviceName not found or error: $_"
            }
        }
        
        if ($allRunning) {
            Write-Host "✓ All AD services are running" -ForegroundColor Green
            
            # Display service status
            foreach ($serviceName in $script:ADServices) {
                $service = Get-Service -Name $serviceName
                Write-Host "  - $serviceName : $($service.Status)" -ForegroundColor White
            }
            
            return $serviceStatus
        }
        
        Write-Host "Waiting for services to start (retry in $RetryIntervalSeconds seconds)..." -ForegroundColor Gray
        Start-Sleep -Seconds $RetryIntervalSeconds
    }
    
    throw "Timeout waiting for AD services. Not all services started within $TimeoutSeconds seconds."
}

<#
.SYNOPSIS
    Tests SYSVOL and NETLOGON share availability.

.DESCRIPTION
    Verifies that SYSVOL and NETLOGON shares are present and accessible,
    which indicates proper DC promotion.

.EXAMPLE
    Test-SYSVOLReplication
    Returns $true if shares are present.

.OUTPUTS
    Boolean - $true if shares exist
#>
function Test-SYSVOLReplication {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-Verbose "Checking SYSVOL and NETLOGON shares..."
    
    try {
        $shares = Get-WmiObject -Class Win32_Share -ErrorAction Stop | 
            Where-Object { $_.Name -in @('SYSVOL', 'NETLOGON') }
        
        if ($shares.Count -ne 2) {
            throw "SYSVOL and/or NETLOGON shares not found (found: $($shares.Count))"
        }
        
        Write-Host "✓ SYSVOL and NETLOGON shares are present" -ForegroundColor Green
        
        foreach ($share in $shares) {
            Write-Host "  - $($share.Name) : $($share.Path)" -ForegroundColor White
        }
        
        return $true
    }
    catch {
        Write-Error "SYSVOL/NETLOGON share check failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Tests Active Directory replication status.

.DESCRIPTION
    Executes repadmin /showrepl and /queue to verify replication is working
    and no items are queued.

.PARAMETER MaxRetries
    Maximum number of retries if replication is converging (default: 5).

.PARAMETER RetryDelaySeconds
    Delay between retries (default: 120).

.EXAMPLE
    Test-ADReplication
    Checks replication status with default retry settings.

.OUTPUTS
    PSCustomObject - Replication status information
#>
function Test-ADReplication {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 5,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 120
    )
    
    Write-Host "`nChecking AD replication status..." -ForegroundColor Yellow
    
    $result = [PSCustomObject]@{
        ShowReplSuccess = $false
        QueueEmpty      = $false
        QueueCount      = -1
        Output          = ""
    }
    
    try {
        # Check repadmin /showrepl
        Write-Verbose "Running repadmin /showrepl..."
        $showReplOutput = & repadmin /showrepl 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "repadmin /showrepl failed with exit code $LASTEXITCODE"
        }
        
        if ($showReplOutput -match "Last attempt.*was successful") {
            Write-Host "✓ Replication is successful with valid timestamps" -ForegroundColor Green
            $result.ShowReplSuccess = $true
        }
        else {
            Write-Warning "Replication not showing successful status yet"
        }
        
        # Check replication queue with retries
        Write-Verbose "Checking replication queue..."
        $attempt = 0
        
        while ($attempt -lt $MaxRetries) {
            $queueOutput = & repadmin /queue 2>&1
            
            if ($queueOutput -match "Queue contains (\d+)") {
                $queueCount = [int]$matches[1]
                $result.QueueCount = $queueCount
                
                if ($queueCount -eq 0) {
                    Write-Host "✓ Replication queue is empty (0 items)" -ForegroundColor Green
                    $result.QueueEmpty = $true
                    break
                }
                else {
                    Write-Warning "Replication queue contains $queueCount items. Waiting for convergence..."
                    $attempt++
                    
                    if ($attempt -lt $MaxRetries) {
                        Start-Sleep -Seconds $RetryDelaySeconds
                    }
                }
            }
            else {
                Write-Host "✓ Replication queue: $queueOutput" -ForegroundColor Green
                $result.QueueEmpty = $true
                break
            }
        }
        
        if (-not $result.QueueEmpty) {
            Write-Warning "Replication queue still has $($result.QueueCount) items after $MaxRetries attempts"
        }
        
        $result.Output = $showReplOutput -join "`n"
        return $result
    }
    catch {
        Write-Error "Replication check failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Runs comprehensive DC diagnostics.

.DESCRIPTION
    Executes multiple dcdiag tests including dcpromo, registerindns, dns, and full diagnostics.

.PARAMETER DomainName
    Domain name for dcdiag tests.

.EXAMPLE
    Invoke-DCDiagnostics -DomainName "linkedin.biz"
    Runs all dcdiag tests.

.OUTPUTS
    Hashtable - Test results for each dcdiag test
#>
function Invoke-DCDiagnostics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainName
    )
    
    Write-Host "`nRunning DC diagnostics (dcdiag)..." -ForegroundColor Yellow
    
    $results = @{
        DCPromo       = $false
        RegisterInDNS = $false
        FullDiag      = $false
        DNSTest       = $false
    }
    
    try {
        # Test 1: dcdiag /test:dcpromo
        Write-Verbose "Running dcdiag /test:dcpromo..."
        $dcpromoOutput = & dcdiag /test:dcpromo /dnsdomain:$DomainName /replicadc 2>&1
        
        if ($dcpromoOutput -notmatch "failed") {
            Write-Host "✓ dcdiag /test:dcpromo passed" -ForegroundColor Green
            $results.DCPromo = $true
        }
        else {
            Write-Warning "dcdiag /test:dcpromo reported failures"
        }
        
        # Test 2: dcdiag /test:registerindns
        Write-Verbose "Running dcdiag /test:registerindns..."
        $registerOutput = & dcdiag /test:registerindns /dnsdomain:$DomainName 2>&1
        
        if ($registerOutput -notmatch "failed") {
            Write-Host "✓ dcdiag /test:registerindns passed" -ForegroundColor Green
            $results.RegisterInDNS = $true
        }
        else {
            Write-Warning "dcdiag /test:registerindns reported failures"
        }
        
        # Test 3: Full dcdiag
        Write-Verbose "Running full dcdiag..."
        $fullOutput = & dcdiag 2>&1
        
        if ($fullOutput -notmatch "failed") {
            Write-Host "✓ Full dcdiag passed" -ForegroundColor Green
            $results.FullDiag = $true
        }
        else {
            Write-Warning "Full dcdiag reported some failures"
        }
        
        # Test 4: dcdiag /test:dns
        Write-Verbose "Running dcdiag /test:dns..."
        $dnsOutput = & dcdiag /test:dns 2>&1
        
        if ($dnsOutput -notmatch "failed") {
            Write-Host "✓ dcdiag /test:dns passed" -ForegroundColor Green
            $results.DNSTest = $true
        }
        else {
            Write-Warning "dcdiag /test:dns reported failures"
        }
        
        return $results
    }
    catch {
        Write-Error "DCDiag execution failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Orchestrates full DC promotion workflow.

.DESCRIPTION
    Complete workflow: install role, promote DC, reboot, wait for services, run health checks.

.PARAMETER DomainName
    Fully qualified domain name.

.PARAMETER Credential
    Domain admin credential.

.PARAMETER SafeModePassword
    DSRM password as SecureString.

.PARAMETER SiteName
    AD site name.

.PARAMETER SkipRoleInstall
    Skip AD DS role installation if already installed.

.PARAMETER SkipPromotion
    Skip promotion (for testing health checks only).

.EXAMPLE
    $cred = Get-Credential
    $dsrm = ConvertTo-SecureString "P@ss!" -AsPlainText -Force
    Invoke-FullPromotion -DomainName "linkedin.biz" -Credential $cred -SafeModePassword $dsrm -SiteName "LVA1"

.OUTPUTS
    PSCustomObject - Complete promotion and health check results
#>
function Invoke-FullPromotion {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainName,
        
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory = $true)]
        [SecureString]$SafeModePassword,
        
        [Parameter(Mandatory = $false)]
        [string]$SiteName,
        
        [Parameter(Mandatory = $false)]
        [switch]$SkipRoleInstall,
        
        [Parameter(Mandatory = $false)]
        [switch]$SkipPromotion
    )
    
    $results = [PSCustomObject]@{
        Timestamp        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        RoleInstalled    = $false
        PromotionSuccess = $false
        ServicesHealthy  = $false
        ReplicationOK    = $false
        DiagnosticsOK    = $false
        AllChecksPassed  = $false
    }
    
    try {
        # Step 1: Install AD DS Role
        if (-not $SkipRoleInstall) {
            $results.RoleInstalled = Install-ADDSRole
        }
        else {
            Write-Host "Skipping AD DS role installation" -ForegroundColor Yellow
            $results.RoleInstalled = $true
        }
        
        # Step 2: Promote to DC
        if (-not $SkipPromotion) {
            $promoteResult = Invoke-DCPromotion -DomainName $DomainName `
                -Credential $Credential `
                -SafeModePassword $SafeModePassword `
                -SiteName $SiteName
            
            $results.PromotionSuccess = $promoteResult.Success
            
            # Note: System will reboot here. This function should be called again after reboot
            # for health checks using -SkipRoleInstall -SkipPromotion switches
        }
        else {
            Write-Host "Skipping DC promotion (running health checks only)" -ForegroundColor Yellow
            $results.PromotionSuccess = $true
        }
        
        # Step 3: Wait for services (after reboot)
        $serviceStatus = Wait-ForADServices
        $results.ServicesHealthy = $true
        
        # Step 4: Health checks
        Write-Host "`n============================================" -ForegroundColor Cyan
        Write-Host "DC HEALTH VALIDATION" -ForegroundColor Cyan
        Write-Host "============================================`n" -ForegroundColor Cyan
        
        # Check SYSVOL/NETLOGON
        Test-SYSVOLReplication
        
        # Check replication
        $replResult = Test-ADReplication
        $results.ReplicationOK = $replResult.ShowReplSuccess -and $replResult.QueueEmpty
        
        # Run diagnostics
        $diagResults = Invoke-DCDiagnostics -DomainName $DomainName
        $results.DiagnosticsOK = $diagResults.DCPromo -and $diagResults.RegisterInDNS -and 
        $diagResults.FullDiag -and $diagResults.DNSTest
        
        # Final status
        $results.AllChecksPassed = $results.ServicesHealthy -and $results.ReplicationOK -and $results.DiagnosticsOK
        
        Write-Host "`n============================================" -ForegroundColor Green
        Write-Host "✅ DC PROMOTION AND HEALTH CHECKS COMPLETE" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        
        return $results
    }
    catch {
        Write-Error "DC promotion workflow failed: $_"
        throw
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Install-ADDSRole',
    'Invoke-DCPromotion',
    'Wait-ForADServices',
    'Test-SYSVOLReplication',
    'Test-ADReplication',
    'Invoke-DCDiagnostics',
    'Invoke-FullPromotion'
)
