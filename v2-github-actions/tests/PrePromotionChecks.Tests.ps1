BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "../scripts/modules/PrePromotionChecks.psm1"
    Import-Module $modulePath -Force
}

Describe "PrePromotionChecks Module" {
    Context "Module Import" {
        It "Should import without errors" {
            { Import-Module (Join-Path $PSScriptRoot "../scripts/modules/PrePromotionChecks.psm1") -Force } | Should -Not -Throw
        }
        
        It "Should export Test-DomainMembership function" {
            Get-Command Test-DomainMembership -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        
        It "Should export Invoke-AllPreChecks function" {
            Get-Command Invoke-AllPreChecks -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}
