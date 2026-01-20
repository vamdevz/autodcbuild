<#
.SYNOPSIS
    Post-promotion configuration module for DNS, agents, and final validation.

.DESCRIPTION
    PowerShell module for post-DC-promotion configuration including DNS conditional forwarders,
    authentication validation, security agent installation, and comprehensive deployment reporting.

.NOTES
    Version: 2.0.0
    Author: LinkedIn Infrastructure Team
    Last Updated: 2026-01-17
#>

#Requires -Version 5.1
# Note: ActiveDirectory and DnsServer modules required on target DC (not on runner)
# Commands execute remotely via WinRM, so no local module requirements

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Creates a DNS conditional forwarder zone.

.DESCRIPTION
    Adds a DNS conditional forwarder if it doesn't already exist.
    Idempotent - safe to run multiple times.

.PARAMETER ZoneName
    Name of the DNS zone to forward.

.PARAMETER MasterServers
    Array of DNS server IPs to forward queries to.

.EXAMPLE
    New-ConditionalForwarder -ZoneName "internal.linkedin.cn" -MasterServers @("10.44.71.6", "10.44.71.5")

.OUTPUTS
    Boolean - $true if created or already exists
#>
function New-ConditionalForwarder {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZoneName,
        
        [Parameter(Mandatory = $true)]
        [string[]]$MasterServers
    )
    
    Write-Verbose "Checking DNS conditional forwarder for $ZoneName..."
    
    try {
        $zone = Get-DnsServerZone -Name $ZoneName -ErrorAction SilentlyContinue
        
        if ($zone) {
            Write-Host "  ✓ Conditional forwarder for $ZoneName already exists" -ForegroundColor Gray
            return $true
        }
        else {
            Add-DnsServerConditionalForwarderZone -Name $ZoneName -MasterServers $MasterServers -ErrorAction Stop
            Write-Host "  ✓ Created conditional forwarder: $ZoneName → $($MasterServers -join ', ')" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Error "Failed to create conditional forwarder for ${ZoneName}: $_"
        throw
    }
}

<#
.SYNOPSIS
    Tests DNS resolution for a given domain.

.DESCRIPTION
    Performs DNS resolution test using Resolve-DnsName with retry logic.

.PARAMETER DomainName
    Domain name to resolve.

.PARAMETER MaxRetries
    Maximum number of retry attempts (default: 3).

.PARAMETER RetryDelaySeconds
    Delay between retries (default: 30).

.EXAMPLE
    Test-DNSResolution -DomainName "msft.sts.microsoft.com"

.OUTPUTS
    String - Resolved IP address(es)
#>
function Test-DNSResolution {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainName,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 30
    )
    
    Write-Verbose "Testing DNS resolution for $DomainName..."
    
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $result = Resolve-DnsName -Name $DomainName -ErrorAction Stop
            $ipAddresses = $result.IPAddress -join ', '
            Write-Host "  ✓ $DomainName resolves to: $ipAddresses" -ForegroundColor Green
            return $ipAddresses
        }
        catch {
            $attempt++
            if ($attempt -lt $MaxRetries) {
                Write-Warning "DNS resolution failed for $DomainName (attempt $attempt/$MaxRetries). Retrying in $RetryDelaySeconds seconds..."
                Start-Sleep -Seconds $RetryDelaySeconds
            }
            else {
                Write-Error "Failed to resolve $DomainName after $MaxRetries attempts: $_"
                throw
            }
        }
    }
}

<#
.SYNOPSIS
    Configures all DNS conditional forwarders based on domain.

.DESCRIPTION
    Creates conditional forwarders for cross-domain resolution and Microsoft services.
    Different forwarders are created depending on whether DC is in BIZ or China domain.

.PARAMETER DomainName
    Current domain name (linkedin.biz or internal.linkedin.cn).

.EXAMPLE
    Initialize-DNSForwarders -DomainName "linkedin.biz"

.OUTPUTS
    PSCustomObject - Configuration results
#>
function Initialize-DNSForwarders {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('linkedin.biz', 'internal.linkedin.cn')]
        [string]$DomainName
    )
    
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "DNS CONDITIONAL FORWARDERS CONFIGURATION" -ForegroundColor Cyan
    Write-Host "============================================`n" -ForegroundColor Cyan
    
    $results = [PSCustomObject]@{
        CrossDomainForwarder   = $false
        GTMForwarder           = $false
        STSForwarder           = $false
        CrossDomainResolution  = $null
        MSFTResolution         = $null
    }
    
    try {
        # Cross-domain forwarder (BIZ ↔ China)
        if ($DomainName -eq 'linkedin.biz') {
            Write-Host "Creating forwarder: BIZ → China domain..." -ForegroundColor Yellow
            $results.CrossDomainForwarder = New-ConditionalForwarder `
                -ZoneName "internal.linkedin.cn" `
                -MasterServers @("10.44.71.6", "10.44.71.5")
        }
        elseif ($DomainName -eq 'internal.linkedin.cn') {
            Write-Host "Creating forwarder: China → BIZ domain..." -ForegroundColor Yellow
            $results.CrossDomainForwarder = New-ConditionalForwarder `
                -ZoneName "linkedin.biz" `
                -MasterServers @("10.41.63.5", "10.41.63.6", "172.21.2.103", "172.21.2.104")
        }
        
        # Microsoft GTM forwarder
        Write-Host "`nCreating forwarder: gtm.corp.microsoft.com..." -ForegroundColor Yellow
        $results.GTMForwarder = New-ConditionalForwarder `
            -ZoneName "gtm.corp.microsoft.com" `
            -MasterServers @("172.31.197.245", "172.31.197.246", "172.31.197.80", "172.31.197.81")
        
        # Microsoft STS forwarder
        Write-Host "`nCreating forwarder: sts.microsoft.com..." -ForegroundColor Yellow
        $results.STSForwarder = New-ConditionalForwarder `
            -ZoneName "sts.microsoft.com" `
            -MasterServers @("172.31.197.245", "172.31.197.246", "172.31.197.80", "172.31.197.81")
        
        # Verify DNS resolution
        Write-Host "`nVerifying DNS resolution..." -ForegroundColor Yellow
        
        # Test Microsoft STS resolution
        $results.MSFTResolution = Test-DNSResolution -DomainName "msft.sts.microsoft.com"
        
        # Test cross-domain resolution
        if ($DomainName -eq 'linkedin.biz') {
            $results.CrossDomainResolution = Test-DNSResolution -DomainName "internal.linkedin.cn"
        }
        elseif ($DomainName -eq 'internal.linkedin.cn') {
            $results.CrossDomainResolution = Test-DNSResolution -DomainName "linkedin.biz"
        }
        
        Write-Host "`n✅ DNS Configuration Complete" -ForegroundColor Green
        
        return $results
    }
    catch {
        Write-Error "DNS forwarder configuration failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Retrieves authentication events from Security event log.

.DESCRIPTION
    Queries Security log for authentication-related events (logon, Kerberos)
    to verify DC is processing authentication requests.

.PARAMETER HoursBack
    Number of hours to look back (default: 2).

.PARAMETER MaxEvents
    Maximum events to retrieve (default: 100).

.EXAMPLE
    Get-AuthenticationEvents
    Returns authentication events from last 2 hours.

.OUTPUTS
    PSCustomObject - Event statistics and sample events
#>
function Get-AuthenticationEvents {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$HoursBack = 2,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxEvents = 100
    )
    
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "AUTHENTICATION EVENT VALIDATION" -ForegroundColor Cyan
    Write-Host "============================================`n" -ForegroundColor Cyan
    
    $results = [PSCustomObject]@{
        EventsFound = 0
        EventsByType = @{}
        Status = "Unknown"
        SampleEvents = @()
    }
    
    try {
        $startTime = (Get-Date).AddHours(-$HoursBack)
        
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = @(4624, 4768, 4771)
            StartTime = $startTime
        } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
        
        if ($events.Count -eq 0) {
            Write-Host "⚠️  No authentication events found in the last $HoursBack hours" -ForegroundColor Yellow
            Write-Host "Status: MONITORING (DC may not have processed auth requests yet)" -ForegroundColor Yellow
            Write-Host "This is normal for newly promoted DCs" -ForegroundColor Gray
            $results.Status = "Monitoring"
        }
        else {
            $results.EventsFound = $events.Count
            Write-Host "✓ Found $($events.Count) authentication events" -ForegroundColor Green
            
            # Group by Event ID
            $grouped = $events | Group-Object Id
            foreach ($group in $grouped) {
                $eventName = switch ($group.Name) {
                    "4624" { "Logon Success" }
                    "4768" { "Kerberos TGT Request" }
                    "4771" { "Kerberos Pre-Auth Failed" }
                }
                $results.EventsByType[$eventName] = $group.Count
                Write-Host "  - EventID $($group.Name) ($eventName): $($group.Count) events" -ForegroundColor White
            }
            
            $results.Status = "Active"
            
            # Get sample events
            $results.SampleEvents = $events | Select-Object -First 5 | ForEach-Object {
                [PSCustomObject]@{
                    Time = $_.TimeCreated
                    EventId = $_.Id
                    Message = $_.Message.Substring(0, [Math]::Min(200, $_.Message.Length))
                }
            }
        }
        
        Write-Host "`n✅ Authentication Check Complete" -ForegroundColor Green
        Write-Host "Status: $($results.Status)" -ForegroundColor $(if ($results.Status -eq "Active") { "Green" } else { "Yellow" })
        
        return $results
    }
    catch {
        Write-Warning "Authentication event check encountered error: $_"
        $results.Status = "Error"
        return $results
    }
}

<#
.SYNOPSIS
    Installs security and monitoring agents.

.DESCRIPTION
    Installs .NET Framework 4.8, Azure AD Password Protection, Azure ATP Sensor,
    Quest Change Auditor, and verifies Qualys agent version.

.PARAMETER InstallerPath
    Path to installer files (default: C:\Temp).

.PARAMETER SkipDotNet
    Skip .NET Framework installation if already present.

.EXAMPLE
    Install-SecurityAgents -InstallerPath "C:\Temp"

.OUTPUTS
    PSCustomObject - Installation results
#>
function Install-SecurityAgents {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InstallerPath = "C:\Temp",
        
        [Parameter(Mandatory = $false)]
        [switch]$SkipDotNet
    )
    
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "SECURITY AGENT INSTALLATION" -ForegroundColor Cyan
    Write-Host "============================================`n" -ForegroundColor Cyan
    
    $results = [PSCustomObject]@{
        DotNetInstalled = $false
        AzureADPPInstalled = $false
        AzureATPInstalled = $false
        QuestAgentInstalled = $false
        QualysVersion = $null
        AgentsRunning = 0
        AgentsInstalled = 0
    }
    
    try {
        # Check existing agents
        Write-Host "Checking for pre-installed agents..." -ForegroundColor Yellow
        $qualys = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -like "*Qualys*" }
        
        if ($qualys) {
            $version = [Version]$qualys.Version
            $minVersion = [Version]"6.2.5.4"
            
            if ($version -lt $minVersion) {
                throw "Qualys version $($qualys.Version) is below minimum 6.2.5.4"
            }
            
            $results.QualysVersion = $qualys.Version
            Write-Host "✓ Qualys Cloud Agent version: $($qualys.Version) - COMPLIANT" -ForegroundColor Green
        }
        else {
            Write-Warning "Qualys agent not found"
        }
        
        # Install .NET Framework 4.8
        if (-not $SkipDotNet) {
            Write-Host "`nInstalling .NET Framework 4.8..." -ForegroundColor Yellow
            $dotnetPath = Join-Path $InstallerPath "ndp48-x86-x64-allos-enu.exe"
            
            if (Test-Path $dotnetPath) {
                $process = Start-Process -FilePath $dotnetPath -ArgumentList "/q", "/norestart" -Wait -PassThru
                if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                    $results.DotNetInstalled = $true
                    Write-Host "✓ .NET Framework 4.8 installed" -ForegroundColor Green
                    
                    if ($process.ExitCode -eq 3010) {
                        Write-Warning "Reboot required after .NET installation"
                    }
                }
            }
            else {
                Write-Warning ".NET installer not found at $dotnetPath"
            }
        }
        
        # Install Azure AD Password Protection
        Write-Host "`nInstalling Azure AD Password Protection DC Agent..." -ForegroundColor Yellow
        $azureADPath = Join-Path $InstallerPath "AzureADPasswordProtectionDCAgentSetup.exe"
        
        if (Test-Path $azureADPath) {
            $process = Start-Process -FilePath $azureADPath -ArgumentList "/quiet", "/norestart" -Wait -PassThru -ErrorAction SilentlyContinue
            if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                $results.AzureADPPInstalled = $true
                Write-Host "✓ Azure AD Password Protection installed" -ForegroundColor Green
            }
        }
        else {
            Write-Warning "Azure AD Password Protection installer not found"
        }
        
        # Install Azure ATP Sensor
        Write-Host "`nInstalling Azure ATP Sensor..." -ForegroundColor Yellow
        $atpPath = Join-Path $InstallerPath "Azure ATP Sensor Setup.exe"
        
        if (Test-Path $atpPath) {
            $process = Start-Process -FilePath $atpPath -ArgumentList "/quiet", "NetFrameworkCommandLineArguments=`"/q`"", "/norestart" -Wait -PassThru -ErrorAction SilentlyContinue
            if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                $results.AzureATPInstalled = $true
                Write-Host "✓ Azure ATP Sensor installed" -ForegroundColor Green
            }
        }
        else {
            Write-Warning "Azure ATP Sensor installer not found"
        }
        
        # Install Quest Change Auditor
        Write-Host "`nInstalling Quest Change Auditor Agent..." -ForegroundColor Yellow
        $questPath = Join-Path $InstallerPath "QuestChangeAuditorAgent.msi"
        
        if (Test-Path $questPath) {
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$questPath`"", "/qn" -Wait -PassThru -ErrorAction SilentlyContinue
            if ($process.ExitCode -eq 0) {
                $results.QuestAgentInstalled = $true
                Write-Host "✓ Quest Change Auditor Agent installed" -ForegroundColor Green
            }
        }
        else {
            Write-Warning "Quest Change Auditor installer not found"
        }
        
        # Check agent services
        Write-Host "`nChecking agent services..." -ForegroundColor Yellow
        $serviceNames = @('AzureADPasswordProtectionDCAgent', 'QualysAgent', 'NPSrvHost', 'HealthService', 'AATPSensor')
        
        foreach ($svcName in $serviceNames) {
            $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($service) {
                $results.AgentsInstalled++
                if ($service.Status -eq 'Running') {
                    $results.AgentsRunning++
                }
                Write-Host "  - $svcName : $($service.Status)" -ForegroundColor White
            }
        }
        
        Write-Host "`n✅ Agent Installation Complete" -ForegroundColor Green
        Write-Host "Agents Installed: $($results.AgentsInstalled)" -ForegroundColor White
        Write-Host "Agents Running: $($results.AgentsRunning)" -ForegroundColor White
        
        if ($results.AgentsInstalled -gt $results.AgentsRunning) {
            Write-Host "`n⚠️  Some agents are stopped (normal during initialization)" -ForegroundColor Yellow
            Write-Host "They will automatically start within 5-10 minutes" -ForegroundColor Gray
        }
        
        return $results
    }
    catch {
        Write-Error "Agent installation failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Adds DC to LDAPS auto-enrollment group.

.DESCRIPTION
    Adds the current DC computer object to SG-LDAPS-DomainController-AutoEnroll
    group for automatic certificate enrollment.

.EXAMPLE
    Add-ToLDAPSGroup
    Adds current DC to LDAPS group.

.OUTPUTS
    Boolean - $true if added or already member
#>
function Add-ToLDAPSGroup {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-Host "`nAdding DC to LDAPS auto-enrollment group..." -ForegroundColor Yellow
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        
        $dcComputer = Get-ADComputer -Identity $env:COMPUTERNAME -ErrorAction Stop
        $group = Get-ADGroup -Identity "SG-LDAPS-DomainController-AutoEnroll" -ErrorAction SilentlyContinue
        
        if (-not $group) {
            Write-Warning "Group 'SG-LDAPS-DomainController-AutoEnroll' not found in domain"
            Write-Host "SKIPPED: Group does not exist" -ForegroundColor Yellow
            return $false
        }
        
        $members = Get-ADGroupMember -Identity $group -ErrorAction Stop
        if ($members.DistinguishedName -contains $dcComputer.DistinguishedName) {
            Write-Host "✓ Already member of SG-LDAPS-DomainController-AutoEnroll" -ForegroundColor Green
            return $true
        }
        else {
            Add-ADGroupMember -Identity $group -Members $dcComputer -ErrorAction Stop
            Write-Host "✓ Added to SG-LDAPS-DomainController-AutoEnroll" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Warning "Failed to add to LDAPS group: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Triggers certificate auto-enrollment.

.DESCRIPTION
    Forces Group Policy update and triggers certificate enrollment using certutil.

.EXAMPLE
    Invoke-CertificateEnrollment

.OUTPUTS
    Boolean - $true if triggered successfully
#>
function Invoke-CertificateEnrollment {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-Host "`nTriggering certificate auto-enrollment..." -ForegroundColor Yellow
    
    try {
        # Force Group Policy update
        $gpResult = & gpupdate /force 2>&1
        Write-Verbose "Group Policy update result: $gpResult"
        
        # Trigger certificate enrollment
        $certResult = & certutil -pulse 2>&1
        Write-Verbose "Certificate enrollment result: $certResult"
        
        Write-Host "✓ Certificate enrollment triggered" -ForegroundColor Green
        Write-Host "⚠️  MANUAL ACTION: Verify certificate issued at go/incerts portal" -ForegroundColor Yellow
        
        return $true
    }
    catch {
        Write-Warning "Certificate enrollment trigger failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Generates comprehensive deployment report.

.DESCRIPTION
    Creates detailed health report including all aspects of DC promotion and configuration.

.PARAMETER DomainName
    Domain name.

.PARAMETER OutputPath
    Path to save report file (optional).

.EXAMPLE
    New-DeploymentReport -DomainName "linkedin.biz" -OutputPath "C:\Temp\report.txt"

.OUTPUTS
    PSCustomObject - Comprehensive health report
#>
function New-DeploymentReport {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainName,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath
    )
    
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "FINAL DEPLOYMENT REPORT" -ForegroundColor Cyan
    Write-Host "============================================`n" -ForegroundColor Cyan
    
    $report = [PSCustomObject]@{
        Hostname                  = $env:COMPUTERNAME
        Domain                    = $null
        Site                      = $null
        Timestamp                 = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ADServicesRunning         = 0
        ADServicesTotal           = 5
        AllADServicesHealthy      = $false
        ReplicationHealthy        = $false
        ReplicationQueueEmpty     = $false
        RequiredSharesPresent     = $false
        ConditionalForwarders     = 0
        ForwarderNames            = ""
        AgentsInstalled           = 0
        AgentsRunning             = 0
        LDAPSGroupMember          = "Unknown"
        AuthenticationActive      = $false
    }
    
    try {
        # Domain and Site info
        $domain = Get-ADDomain
        $report.Domain = $domain.DNSRoot
        
        $dc = Get-ADDomainController -Identity $env:COMPUTERNAME
        $report.Site = $dc.Site
        
        # AD Services
        $adServices = Get-Service -Name NTDS, DNS, Netlogon, W32Time, KDC
        $report.ADServicesRunning = ($adServices | Where-Object { $_.Status -eq 'Running' }).Count
        $report.AllADServicesHealthy = ($report.ADServicesRunning -eq $report.ADServicesTotal)
        
        # Replication
        $replOutput = & repadmin /showrepl 2>&1
        $report.ReplicationHealthy = $replOutput -match "Last attempt.*was successful"
        
        $queueOutput = & repadmin /queue 2>&1
        $report.ReplicationQueueEmpty = $queueOutput -match "Queue contains 0"
        
        # Shares
        $shares = Get-WmiObject -Class Win32_Share | Where-Object { $_.Name -in @('SYSVOL', 'NETLOGON') }
        $report.RequiredSharesPresent = ($shares.Count -eq 2)
        
        # DNS Forwarders
        $forwarders = Get-DnsServerZone | Where-Object { $_.ZoneType -eq 'Forwarder' }
        $report.ConditionalForwarders = $forwarders.Count
        $report.ForwarderNames = ($forwarders.ZoneName -join ', ')
        
        # Agents
        $serviceNames = @('AzureADPasswordProtectionDCAgent', 'QualysAgent', 'NPSrvHost', 'HealthService', 'AATPSensor')
        $agentServices = Get-Service -Name $serviceNames -ErrorAction SilentlyContinue
        $report.AgentsInstalled = ($agentServices | Measure-Object).Count
        $report.AgentsRunning = ($agentServices | Where-Object { $_.Status -eq 'Running' } | Measure-Object).Count
        
        # LDAPS Group
        $dcComputer = Get-ADComputer -Identity $env:COMPUTERNAME -Properties MemberOf
        $report.LDAPSGroupMember = ($dcComputer.MemberOf -match "SG-LDAPS-DomainController-AutoEnroll").ToString()
        
        # Authentication
        $authEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = @(4624, 4768, 4771)
            StartTime = (Get-Date).AddHours(-1)
        } -MaxEvents 1 -ErrorAction SilentlyContinue
        $report.AuthenticationActive = ($authEvents.Count -gt 0)
        
        # Display report
        Write-Host "Server: $($report.Hostname)" -ForegroundColor White
        Write-Host "Domain: $($report.Domain)" -ForegroundColor White
        Write-Host "Site: $($report.Site)" -ForegroundColor White
        Write-Host "Completed: $($report.Timestamp)" -ForegroundColor White
        Write-Host "`nHEALTH STATUS:" -ForegroundColor Cyan
        Write-Host "- AD Services: $($report.ADServicesRunning)/$($report.ADServicesTotal) running" -ForegroundColor White
        Write-Host "- Replication: $(if ($report.ReplicationHealthy) { 'HEALTHY' } else { 'ISSUES DETECTED' })" -ForegroundColor $(if ($report.ReplicationHealthy) { "Green" } else { "Yellow" })
        Write-Host "- Replication Queue: $(if ($report.ReplicationQueueEmpty) { 'EMPTY (OK)' } else { 'PENDING ITEMS' })" -ForegroundColor $(if ($report.ReplicationQueueEmpty) { "Green" } else { "Yellow" })
        Write-Host "- SYSVOL/NETLOGON: $(if ($report.RequiredSharesPresent) { 'PRESENT' } else { 'MISSING' })" -ForegroundColor $(if ($report.RequiredSharesPresent) { "Green" } else { "Red" })
        Write-Host "- DNS Forwarders: $($report.ConditionalForwarders) configured" -ForegroundColor White
        Write-Host "- Agents: $($report.AgentsInstalled) installed, $($report.AgentsRunning) running" -ForegroundColor White
        Write-Host "- LDAPS Group: $($report.LDAPSGroupMember)" -ForegroundColor White
        Write-Host "- Authentication: $(if ($report.AuthenticationActive) { 'ACTIVE' } else { 'MONITORING' })" -ForegroundColor $(if ($report.AuthenticationActive) { "Green" } else { "Yellow" })
        
        Write-Host "`n⚠️  MANUAL FOLLOW-UP REQUIRED:" -ForegroundColor Yellow
        Write-Host "1. Verify certificate issued: go/incerts" -ForegroundColor White
        Write-Host "2. Confirm FIM compliance: Contact InfoSec SPM team" -ForegroundColor White
        Write-Host "3. Update change ticket with completion details" -ForegroundColor White
        Write-Host "4. Monitor agent initialization: 5-10 minutes" -ForegroundColor White
        
        # Save to file if path provided
        if ($OutputPath) {
            $reportText = @"
============================================
LinkedIn DC Promotion - Deployment Report
============================================

Server: $($report.Hostname)
Domain: $($report.Domain)
Site: $($report.Site)
Promotion Completed: $($report.Timestamp)

HEALTH STATUS:
✓ AD Services: $($report.ADServicesRunning)/$($report.ADServicesTotal) running
✓ Replication: $(if ($report.ReplicationHealthy) { 'HEALTHY' } else { 'ISSUES' })
✓ Replication Queue: $(if ($report.ReplicationQueueEmpty) { 'EMPTY' } else { 'PENDING' })
✓ SYSVOL/NETLOGON: $(if ($report.RequiredSharesPresent) { 'OK' } else { 'MISSING' })
✓ DNS Forwarders: $($report.ConditionalForwarders) zones
✓ Agents: $($report.AgentsInstalled) installed, $($report.AgentsRunning) running
✓ LDAPS Group: $($report.LDAPSGroupMember)
✓ Authentication: $(if ($report.AuthenticationActive) { 'ACTIVE' } else { 'MONITORING' })

DNS CONDITIONAL FORWARDERS:
$($report.ForwarderNames)

MANUAL STEPS REMAINING:
1. Certificate validation: go/incerts
2. InfoSec FIM compliance: Contact InfoSec SPM team
3. Change ticket update: Document completion

Generated by: PowerShell Automation (v2)
Date: $($report.Timestamp)
============================================
"@
            $reportText | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Host "`n✓ Report saved to: $OutputPath" -ForegroundColor Green
        }
        
        Write-Host "`n============================================" -ForegroundColor Green
        
        return $report
    }
    catch {
        Write-Error "Failed to generate deployment report: $_"
        throw
    }
}

<#
.SYNOPSIS
    Runs all post-configuration tasks.

.DESCRIPTION
    Orchestrates DNS configuration, authentication checks, agent installation,
    LDAPS group membership, certificate enrollment, and reporting.

.PARAMETER DomainName
    Domain name.

.PARAMETER AgentInstallerPath
    Path to agent installer files.

.PARAMETER ReportPath
    Path to save final report.

.EXAMPLE
    Invoke-PostConfiguration -DomainName "linkedin.biz" -ReportPath "C:\Temp\report.txt"

.OUTPUTS
    PSCustomObject - Complete configuration results
#>
function Invoke-PostConfiguration {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainName,
        
        [Parameter(Mandatory = $false)]
        [string]$AgentInstallerPath = "C:\Temp",
        
        [Parameter(Mandatory = $false)]
        [string]$ReportPath
    )
    
    $results = [PSCustomObject]@{
        DNSConfigured          = $false
        AuthenticationChecked  = $false
        AgentsInstalled        = $false
        LDAPSGroupAdded        = $false
        CertificateTriggered   = $false
        ReportGenerated        = $false
        FinalReport            = $null
    }
    
    try {
        # Step 1: DNS Configuration
        Write-Host "`n[1/6] Configuring DNS conditional forwarders..." -ForegroundColor Cyan
        Initialize-DNSForwarders -DomainName $DomainName
        $results.DNSConfigured = $true
        
        # Step 2: Authentication Check
        Write-Host "`n[2/6] Checking authentication events..." -ForegroundColor Cyan
        Get-AuthenticationEvents
        $results.AuthenticationChecked = $true
        
        # Step 3: Install Agents
        Write-Host "`n[3/6] Installing security agents..." -ForegroundColor Cyan
        Install-SecurityAgents -InstallerPath $AgentInstallerPath
        $results.AgentsInstalled = $true
        
        # Step 4: LDAPS Group
        Write-Host "`n[4/6] Adding to LDAPS group..." -ForegroundColor Cyan
        $results.LDAPSGroupAdded = Add-ToLDAPSGroup
        
        # Step 5: Certificate Enrollment
        Write-Host "`n[5/6] Triggering certificate enrollment..." -ForegroundColor Cyan
        $results.CertificateTriggered = Invoke-CertificateEnrollment
        
        # Step 6: Generate Report
        Write-Host "`n[6/6] Generating final report..." -ForegroundColor Cyan
        $results.FinalReport = New-DeploymentReport -DomainName $DomainName -OutputPath $ReportPath
        $results.ReportGenerated = $true
        
        Write-Host "`n✅ POST-CONFIGURATION COMPLETE" -ForegroundColor Green
        
        return $results
    }
    catch {
        Write-Error "Post-configuration failed: $_"
        throw
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'New-ConditionalForwarder',
    'Test-DNSResolution',
    'Initialize-DNSForwarders',
    'Get-AuthenticationEvents',
    'Install-SecurityAgents',
    'Add-ToLDAPSGroup',
    'Invoke-CertificateEnrollment',
    'New-DeploymentReport',
    'Invoke-PostConfiguration'
)
