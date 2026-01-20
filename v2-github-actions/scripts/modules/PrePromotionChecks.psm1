<#
.SYNOPSIS
    Pre-promotion validation checks for Domain Controller promotion.

.DESCRIPTION
    PowerShell module containing validation functions to verify server readiness
    before DC promotion. Checks domain membership, DNS configuration, disk space,
    DC connectivity, and AD module availability.

.NOTES
    Version: 2.0.0
    Author: LinkedIn Infrastructure Team
    Last Updated: 2026-01-17
#>

#Requires -Version 5.1
# Note: Commands execute remotely via WinRM, so no RunAsAdministrator requirement on runner

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Module-level variables
$script:MinDiskSpaceGB = 20

<#
.SYNOPSIS
    Tests if the server is joined to a domain.

.DESCRIPTION
    Validates that the server is a member of an Active Directory domain
    before attempting DC promotion.

.EXAMPLE
    Test-DomainMembership
    Returns domain name if joined, throws error if not.

.OUTPUTS
    String - Domain name if successful
#>
function Test-DomainMembership {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    Write-Verbose "Checking domain membership status..."
    
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        
        if ($computerSystem.PartOfDomain -ne $true) {
            throw "Server is not domain-joined. Domain join required before DC promotion."
        }
        
        $domainName = $computerSystem.Domain
        Write-Host "✓ Server is member of domain: $domainName" -ForegroundColor Green
        
        return $domainName
    }
    catch {
        Write-Error "Domain membership check failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Validates DNS configuration points to domain controllers.

.DESCRIPTION
    Checks that DNS client settings are configured and DNS servers
    are reachable for domain name resolution.

.EXAMPLE
    Test-DNSConfiguration
    Returns array of configured DNS servers.

.OUTPUTS
    String[] - Array of DNS server IP addresses
#>
function Test-DNSConfiguration {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    
    Write-Verbose "Checking DNS configuration..."
    
    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | 
            Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } |
            Select-Object -ExpandProperty ServerAddresses |
            Where-Object { $_ -ne $null }
        
        if ($dnsServers.Count -eq 0) {
            throw "No DNS servers configured on non-loopback interfaces"
        }
        
        $dnsServerList = $dnsServers -join ', '
        Write-Host "✓ DNS servers configured: $dnsServerList" -ForegroundColor Green
        
        return $dnsServers
    }
    catch {
        Write-Error "DNS configuration check failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Tests connectivity to the primary domain controller.

.DESCRIPTION
    Verifies TCP connectivity to the primary DC on LDAP port (389)
    to ensure successful domain operations.

.PARAMETER PrimaryDC
    IP address or hostname of the primary domain controller.

.PARAMETER Port
    Port number to test (default: 389 for LDAP).

.EXAMPLE
    Test-DCConnectivity -PrimaryDC "10.41.63.5"
    Tests connectivity to the specified DC.

.OUTPUTS
    Boolean - $true if connectivity successful
#>
function Test-DCConnectivity {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrimaryDC,
        
        [Parameter(Mandatory = $false)]
        [int]$Port = 389
    )
    
    Write-Verbose "Testing connectivity to primary DC: $PrimaryDC on port $Port..."
    
    try {
        $result = Test-NetConnection -ComputerName $PrimaryDC -Port $Port -WarningAction SilentlyContinue -ErrorAction Stop
        
        if (-not $result.TcpTestSucceeded) {
            throw "Cannot reach primary DC $PrimaryDC on port $Port (LDAP)"
        }
        
        Write-Host "✓ Primary DC $PrimaryDC is reachable on port $Port" -ForegroundColor Green
        
        return $true
    }
    catch {
        Write-Error "DC connectivity check failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Validates disk space availability on specified drives.

.DESCRIPTION
    Checks free disk space on D: and E: drives (or specified drives)
    to ensure sufficient space for AD database and SYSVOL.

.PARAMETER RequiredDrives
    Array of drive letters to check (default: @('D', 'E')).

.PARAMETER MinimumFreeSpaceGB
    Minimum free space required in GB (default: 20).

.EXAMPLE
    Test-DiskSpace
    Checks default drives with default minimum space.

.EXAMPLE
    Test-DiskSpace -RequiredDrives @('D', 'E', 'F') -MinimumFreeSpaceGB 50
    Checks custom drives with higher space requirement.

.OUTPUTS
    Hashtable - Drive letters and their free space in GB
#>
function Test-DiskSpace {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$RequiredDrives = @('D', 'E'),
        
        [Parameter(Mandatory = $false)]
        [int]$MinimumFreeSpaceGB = $script:MinDiskSpaceGB
    )
    
    Write-Verbose "Checking disk space on drives: $($RequiredDrives -join ', ')..."
    
    $diskInfo = @{}
    
    try {
        $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction Stop | 
            Where-Object { $_.Name -in $RequiredDrives }
        
        if ($drives.Count -eq 0) {
            throw "None of the required drives ($($RequiredDrives -join ', ')) were found"
        }
        
        foreach ($drive in $drives) {
            $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
            $diskInfo[$drive.Name] = $freeSpaceGB
            
            if ($freeSpaceGB -lt $MinimumFreeSpaceGB) {
                throw "Drive $($drive.Name): has only $freeSpaceGB GB free (minimum $MinimumFreeSpaceGB GB required)"
            }
            
            Write-Host "✓ Drive $($drive.Name): $freeSpaceGB GB free - OK" -ForegroundColor Green
        }
        
        return $diskInfo
    }
    catch {
        Write-Error "Disk space check failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Verifies Active Directory PowerShell module is available.

.DESCRIPTION
    Attempts to import the ActiveDirectory module which is required
    for DC management operations.

.EXAMPLE
    Test-ADModule
    Returns $true if module loads successfully.

.OUTPUTS
    Boolean - $true if module is available
#>
function Test-ADModule {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    Write-Verbose "Checking Active Directory module availability..."
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Host "✓ ActiveDirectory module loaded successfully" -ForegroundColor Green
        
        return $true
    }
    catch {
        Write-Error "AD module check failed. Ensure RSAT-AD-PowerShell feature is installed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Runs all pre-promotion validation checks.

.DESCRIPTION
    Orchestrates all validation functions to provide a comprehensive
    pre-flight check before DC promotion. Returns a summary object
    with all check results.

.PARAMETER PrimaryDC
    IP address or hostname of the primary domain controller.

.PARAMETER RequiredDrives
    Array of drive letters to check for disk space.

.PARAMETER MinimumFreeSpaceGB
    Minimum free space required in GB.

.EXAMPLE
    Invoke-AllPreChecks -PrimaryDC "10.41.63.5"
    Runs all checks with default parameters.

.EXAMPLE
    $results = Invoke-AllPreChecks -PrimaryDC "dc01.linkedin.biz" -MinimumFreeSpaceGB 50
    Runs checks and captures results object.

.OUTPUTS
    PSCustomObject - Object containing all check results
#>
function Invoke-AllPreChecks {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrimaryDC,
        
        [Parameter(Mandatory = $false)]
        [string[]]$RequiredDrives = @('D', 'E'),
        
        [Parameter(Mandatory = $false)]
        [int]$MinimumFreeSpaceGB = 20
    )
    
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "PRE-PROMOTION VALIDATION CHECKS" -ForegroundColor Cyan
    Write-Host "============================================`n" -ForegroundColor Cyan
    
    $results = [PSCustomObject]@{
        Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        DomainName        = $null
        DNSServers        = @()
        DCConnectivity    = $false
        DiskSpace         = @{}
        ADModuleAvailable = $false
        AllChecksPassed   = $false
        ErrorMessages     = @()
    }
    
    try {
        # Check 1: Domain Membership
        Write-Host "[1/5] Checking domain membership..." -ForegroundColor Yellow
        $results.DomainName = Test-DomainMembership
        
        # Check 2: DNS Configuration
        Write-Host "`n[2/5] Checking DNS configuration..." -ForegroundColor Yellow
        $results.DNSServers = Test-DNSConfiguration
        
        # Check 3: DC Connectivity
        Write-Host "`n[3/5] Testing DC connectivity..." -ForegroundColor Yellow
        $results.DCConnectivity = Test-DCConnectivity -PrimaryDC $PrimaryDC
        
        # Check 4: Disk Space
        Write-Host "`n[4/5] Checking disk space..." -ForegroundColor Yellow
        $results.DiskSpace = Test-DiskSpace -RequiredDrives $RequiredDrives -MinimumFreeSpaceGB $MinimumFreeSpaceGB
        
        # Check 5: AD Module
        Write-Host "`n[5/5] Verifying AD module..." -ForegroundColor Yellow
        $results.ADModuleAvailable = Test-ADModule
        
        # All checks passed
        $results.AllChecksPassed = $true
        
        # Display summary
        Write-Host "`n============================================" -ForegroundColor Green
        Write-Host "✅ PRE-PROMOTION CHECKS PASSED" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "Domain:      $($results.DomainName)" -ForegroundColor White
        Write-Host "DNS Servers: $($results.DNSServers -join ', ')" -ForegroundColor White
        Write-Host "Primary DC:  $PrimaryDC (reachable)" -ForegroundColor White
        Write-Host "AD Module:   Available" -ForegroundColor White
        
        foreach ($drive in $results.DiskSpace.Keys | Sort-Object) {
            Write-Host "Drive ${drive}:     $($results.DiskSpace[$drive]) GB free" -ForegroundColor White
        }
        
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "✅ Ready for DC Promotion" -ForegroundColor Green
        Write-Host "============================================`n" -ForegroundColor Green
        
        return $results
    }
    catch {
        $results.AllChecksPassed = $false
        $results.ErrorMessages += $_.Exception.Message
        
        Write-Host "`n============================================" -ForegroundColor Red
        Write-Host "❌ PRE-PROMOTION CHECKS FAILED" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Red
        Write-Error "Pre-promotion validation failed: $_"
        
        throw
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Test-DomainMembership',
    'Test-DNSConfiguration',
    'Test-DCConnectivity',
    'Test-DiskSpace',
    'Test-ADModule',
    'Invoke-AllPreChecks'
)
