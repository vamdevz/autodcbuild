<#
.SYNOPSIS
    Main orchestrator for Domain Controller promotion pipeline.

.DESCRIPTION
    Comprehensive DC promotion pipeline that orchestrates all phases:
    - Pre-promotion validation
    - DC promotion and health checks
    - Post-configuration (DNS, agents, reporting)
    
    Integrates with Azure Key Vault for secure credential management.

.PARAMETER Environment
    Target environment (staging or production).

.PARAMETER ConfigPath
    Path to configuration JSON file.

.PARAMETER TargetDC
    Target DC hostname to promote (optional, can be in config).

.PARAMETER KeyVaultName
    Azure Key Vault name for retrieving secrets.

.PARAMETER SkipPreChecks
    Skip pre-promotion validation checks.

.PARAMETER SkipPromotion
    Skip DC promotion (for post-reboot health checks only).

.PARAMETER SkipPostConfig
    Skip post-configuration tasks.

.EXAMPLE
    .\Invoke-DCPromotionPipeline.ps1 -Environment staging -ConfigPath "./config/staging.json" -KeyVaultName "dc-promo-kv"

.EXAMPLE
    .\Invoke-DCPromotionPipeline.ps1 -Environment production -TargetDC "lva1-dc03" -KeyVaultName "dc-promo-kv"

.EXAMPLE
    # Post-reboot health checks only
    .\Invoke-DCPromotionPipeline.ps1 -Environment production -SkipPreChecks -SkipPromotion -KeyVaultName "dc-promo-kv"

.NOTES
    Version: 2.0.0
    Author: LinkedIn Infrastructure Team
    Requires: Azure PowerShell Module (Az.KeyVault)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('lab', 'staging', 'production')]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,
    
    [Parameter(Mandatory = $false)]
    [string]$TargetDC,
    
    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipPreChecks,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipPromotion,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipPostConfig,
    
    [Parameter(Mandatory = $false)]
    [switch]$UseLocalSecrets
)

#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script variables
$script:ScriptPath = $PSScriptRoot
$script:ModulePath = Join-Path $ScriptPath "modules"
$script:ConfigBasePath = Join-Path (Split-Path $ScriptPath -Parent) "config"
$script:StartTime = Get-Date

#region Helper Functions

function Write-PipelineLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        'Info' { 'White' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
    
    # Also write to verbose stream
    Write-Verbose "[$timestamp] $Message"
}

function Get-AzureKeyVaultSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultName,
        
        [Parameter(Mandatory = $true)]
        [string]$SecretName
    )
    
    try {
        Write-PipelineLog "Retrieving secret '$SecretName' from Key Vault '$VaultName'..." -Level Info
        
        # Check if Az.KeyVault module is available
        if (-not (Get-Module -Name Az.KeyVault -ListAvailable)) {
            throw "Az.KeyVault module not found. Install with: Install-Module -Name Az.KeyVault"
        }
        
        Import-Module Az.KeyVault -ErrorAction Stop
        
        $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -AsPlainText -ErrorAction Stop
        
        Write-PipelineLog "Successfully retrieved secret '$SecretName'" -Level Success
        return $secret
    }
    catch {
        Write-PipelineLog "Failed to retrieve secret '$SecretName': $_" -Level Error
        throw
    }
}

function Get-ConfigurationFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        Write-PipelineLog "Loading configuration from $Path..." -Level Info
        
        if (-not (Test-Path $Path)) {
            throw "Configuration file not found: $Path"
        }
        
        $config = Get-Content -Path $Path -Raw | ConvertFrom-Json
        
        Write-PipelineLog "Configuration loaded successfully" -Level Success
        return $config
    }
    catch {
        Write-PipelineLog "Failed to load configuration: $_" -Level Error
        throw
    }
}

#endregion

#region Main Pipeline

try {
    Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║         LinkedIn DC Promotion Pipeline v2.0                 ║
║         PowerShell + Azure Integration                      ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

    Write-PipelineLog "Starting DC Promotion Pipeline" -Level Info
    Write-PipelineLog "Environment: $Environment" -Level Info
    Write-PipelineLog "Execution Start: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info
    
    #region Load Modules
    
    Write-PipelineLog "Loading PowerShell modules..." -Level Info
    
    $modules = @('PrePromotionChecks', 'DCPromotion', 'PostConfiguration')
    foreach ($moduleName in $modules) {
        $modulePath = Join-Path $script:ModulePath "$moduleName.psm1"
        
        if (-not (Test-Path $modulePath)) {
            throw "Module not found: $modulePath"
        }
        
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-PipelineLog "Loaded module: $moduleName" -Level Success
    }
    
    #endregion
    
    #region Load Configuration
    
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $script:ConfigBasePath "$Environment.json"
    }
    
    $config = Get-ConfigurationFromFile -Path $ConfigPath
    
    # Override target DC if specified
    if ($TargetDC) {
        $config.target_host = $TargetDC
    }
    
    Write-PipelineLog "Domain: $($config.domain_name)" -Level Info
    Write-PipelineLog "Target DC: $($config.target_host)" -Level Info
    Write-PipelineLog "Site: $($config.ad_site_name)" -Level Info
    
    #endregion
    
    #region Retrieve Secrets
    
    Write-PipelineLog "Retrieving secrets..." -Level Info
    
    if ($UseLocalSecrets) {
        Write-PipelineLog "Using local secrets (development mode)" -Level Warning
        
        # Prompt for credentials
        $domainCred = Get-Credential -Message "Enter domain admin credentials"
        $dsrmPassword = Read-Host -Prompt "Enter DSRM password" -AsSecureString
    }
    elseif ($KeyVaultName) {
        Write-PipelineLog "Retrieving secrets from Azure Key Vault: $KeyVaultName" -Level Info
        
        # Retrieve secrets from Key Vault
        $domainAdminUser = Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName "dc-domain-admin-username"
        $domainAdminPassword = Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName "dc-domain-admin-password"
        $dsrmPasswordPlain = Get-AzureKeyVaultSecret -VaultName $KeyVaultName -SecretName "dc-dsrm-password"
        
        # Convert to secure credentials
        $securePassword = ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force
        $domainCred = New-Object System.Management.Automation.PSCredential($domainAdminUser, $securePassword)
        $dsrmPassword = ConvertTo-SecureString $dsrmPasswordPlain -AsPlainText -Force
        
        Write-PipelineLog "Secrets retrieved successfully" -Level Success
    }
    else {
        throw "Either -KeyVaultName or -UseLocalSecrets must be specified"
    }
    
    #endregion
    
    #region Production Confirmation
    
    if ($Environment -eq 'production' -and -not $SkipPromotion) {
        Write-Host "`n⚠️  WARNING: You are about to promote a PRODUCTION domain controller!" -ForegroundColor Yellow -BackgroundColor Red
        Write-Host "Environment: PRODUCTION" -ForegroundColor Yellow
        Write-Host "Target DC: $($config.target_host)" -ForegroundColor Yellow
        Write-Host "Domain: $($config.domain_name)" -ForegroundColor Yellow
        Write-Host "`nThis operation will:" -ForegroundColor Yellow
        Write-Host "  - Install AD DS role" -ForegroundColor White
        Write-Host "  - Promote to Domain Controller" -ForegroundColor White
        Write-Host "  - Reboot the server" -ForegroundColor White
        Write-Host "  - Configure DNS and agents" -ForegroundColor White
        
        $confirmation = Read-Host "`nType 'PROMOTE' to continue"
        
        if ($confirmation -ne 'PROMOTE') {
            Write-PipelineLog "Production promotion cancelled by user" -Level Warning
            exit 0
        }
        
        Write-PipelineLog "Production promotion confirmed" -Level Info
    }
    
    #endregion
    
    #region Phase 1: Pre-Promotion Checks
    
    if (-not $SkipPreChecks) {
        Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
        Write-PipelineLog "PHASE 1: PRE-PROMOTION VALIDATION" -Level Info
        Write-Host ("=" * 70) + "`n" -ForegroundColor Cyan
        
        try {
            $preCheckResults = Invoke-AllPreChecks `
                -PrimaryDC $config.primary_dc_ip `
                -RequiredDrives $config.required_drives `
                -MinimumFreeSpaceGB $config.min_disk_space_gb
            
            if (-not $preCheckResults.AllChecksPassed) {
                throw "Pre-promotion checks failed"
            }
            
            Write-PipelineLog "Pre-promotion checks completed successfully" -Level Success
        }
        catch {
            Write-PipelineLog "Pre-promotion checks failed: $_" -Level Error
            throw
        }
    }
    else {
        Write-PipelineLog "Skipping pre-promotion checks (as requested)" -Level Warning
    }
    
    #endregion
    
    #region Phase 2: DC Promotion
    
    if (-not $SkipPromotion) {
        Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
        Write-PipelineLog "PHASE 2: DOMAIN CONTROLLER PROMOTION" -Level Info
        Write-Host ("=" * 70) + "`n" -ForegroundColor Cyan
        
        try {
            $promoteResult = Invoke-FullPromotion `
                -DomainName $config.domain_name `
                -Credential $domainCred `
                -SafeModePassword $dsrmPassword `
                -SiteName $config.ad_site_name `
                -SkipRoleInstall:$false
            
            Write-PipelineLog "DC promotion initiated successfully" -Level Success
            Write-PipelineLog "Server will reboot automatically" -Level Warning
            Write-PipelineLog "After reboot, run this script again with -SkipPreChecks -SkipPromotion flags" -Level Info
            
            # Note: Script will not reach here if promotion succeeds as system will reboot
            exit 0
        }
        catch {
            Write-PipelineLog "DC promotion failed: $_" -Level Error
            throw
        }
    }
    else {
        Write-PipelineLog "Skipping DC promotion (running post-reboot checks)" -Level Warning
    }
    
    #endregion
    
    #region Phase 3: Post-Reboot Health Checks
    
    if ($SkipPromotion) {
        Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
        Write-PipelineLog "PHASE 3: POST-REBOOT HEALTH VALIDATION" -Level Info
        Write-Host ("=" * 70) + "`n" -ForegroundColor Cyan
        
        try {
            # Wait for services
            Write-PipelineLog "Waiting for AD services to start..." -Level Info
            $serviceStatus = Wait-ForADServices -TimeoutSeconds 600 -RetryIntervalSeconds 30
            
            # Run health checks
            Write-PipelineLog "Running comprehensive health checks..." -Level Info
            Test-SYSVOLReplication
            
            $replResult = Test-ADReplication -MaxRetries 5 -RetryDelaySeconds 120
            if (-not ($replResult.ShowReplSuccess -and $replResult.QueueEmpty)) {
                Write-PipelineLog "Replication issues detected but continuing..." -Level Warning
            }
            
            $diagResults = Invoke-DCDiagnostics -DomainName $config.domain_name
            
            Write-PipelineLog "Post-reboot health checks completed" -Level Success
        }
        catch {
            Write-PipelineLog "Post-reboot health checks encountered errors: $_" -Level Warning
            # Continue with post-configuration even if some health checks fail
        }
    }
    
    #endregion
    
    #region Phase 4: Post-Configuration
    
    if (-not $SkipPostConfig) {
        Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
        Write-PipelineLog "PHASE 4: POST-CONFIGURATION" -Level Info
        Write-Host ("=" * 70) + "`n" -ForegroundColor Cyan
        
        try {
            $reportPath = "C:\Temp\DC-Deployment-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
            
            $postConfigResults = Invoke-PostConfiguration `
                -DomainName $config.domain_name `
                -AgentInstallerPath "C:\Temp" `
                -ReportPath $reportPath
            
            Write-PipelineLog "Post-configuration completed successfully" -Level Success
        }
        catch {
            Write-PipelineLog "Post-configuration encountered errors: $_" -Level Warning
            # Non-fatal - report anyway
        }
    }
    else {
        Write-PipelineLog "Skipping post-configuration (as requested)" -Level Warning
    }
    
    #endregion
    
    #region Final Summary
    
    $endTime = Get-Date
    $duration = $endTime - $script:StartTime
    
    Write-Host "`n" + ("=" * 70) -ForegroundColor Green
    Write-Host " PIPELINE EXECUTION COMPLETE " -ForegroundColor Green -BackgroundColor Black
    Write-Host ("=" * 70) -ForegroundColor Green
    
    Write-Host "`nExecution Summary:" -ForegroundColor Cyan
    Write-Host "  Environment: $Environment" -ForegroundColor White
    Write-Host "  Domain: $($config.domain_name)" -ForegroundColor White
    Write-Host "  Target DC: $($config.target_host)" -ForegroundColor White
    Write-Host "  Start Time: $($script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "  End Time: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "  Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
    
    Write-Host "`n✅ Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Verify certificate issued: go/incerts" -ForegroundColor White
    Write-Host "  2. Confirm FIM compliance with InfoSec SPM team" -ForegroundColor White
    Write-Host "  3. Update change ticket" -ForegroundColor White
    Write-Host "  4. Monitor agent initialization (5-10 minutes)" -ForegroundColor White
    
    Write-Host "`n" + ("=" * 70) + "`n" -ForegroundColor Green
    
    Write-PipelineLog "Pipeline execution completed successfully" -Level Success
    
    exit 0
    
    #endregion
}
catch {
    $errorMessage = $_.Exception.Message
    $errorLine = $_.InvocationInfo.ScriptLineNumber
    
    Write-Host "`n" + ("=" * 70) -ForegroundColor Red
    Write-Host " PIPELINE EXECUTION FAILED " -ForegroundColor Red -BackgroundColor Black
    Write-Host ("=" * 70) -ForegroundColor Red
    
    Write-PipelineLog "Pipeline failed with error: $errorMessage" -Level Error
    Write-PipelineLog "Error at line: $errorLine" -Level Error
    Write-PipelineLog "Stack trace: $($_.ScriptStackTrace)" -Level Error
    
    Write-Host "`nFor support, contact: AD Operations Team" -ForegroundColor Yellow
    Write-Host ("=" * 70) + "`n" -ForegroundColor Red
    
    exit 1
}

#endregion
