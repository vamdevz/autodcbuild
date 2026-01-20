# Test Suite

## Pester Tests

This directory contains Pester tests for the PowerShell modules.

### Running Tests

```powershell
# Install Pester
Install-Module -Name Pester -Force -SkipPublisherCheck

# Run all tests
Invoke-Pester -Path ./tests

# Run with coverage
Invoke-Pester -Path ./tests -CodeCoverage ./scripts/modules/*.psm1
```

### Test Structure

- `PrePromotionChecks.Tests.ps1` - Tests for pre-promotion validation module
- Additional test files can be added for other modules

### Note

Full integration tests require Windows Server with AD capabilities.
These tests focus on module structure and syntax validation.
