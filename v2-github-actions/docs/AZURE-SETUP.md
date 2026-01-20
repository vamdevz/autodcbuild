# Azure Setup Guide

Complete guide for configuring Azure Key Vault and OIDC for the DC promotion pipeline.

## Prerequisites

- Azure subscription with Contributor access
- Azure CLI installed (`az` command)
- PowerShell 7+ or Azure Cloud Shell

## Step 1: Create Resource Group

```bash
az group create \
  --name rg-dc-automation \
  --location eastus
```

## Step 2: Create Azure Key Vault

```bash
az keyvault create \
  --name dc-promotion-kv \
  --resource-group rg-dc-automation \
  --location eastus \
  --enable-rbac-authorization
```

## Step 3: Store Secrets in Key Vault

```bash
# Domain admin credentials
az keyvault secret set --vault-name dc-promotion-kv \
  --name dc-domain-admin-username \
  --value "LINKEDIN\\admin"

az keyvault secret set --vault-name dc-promotion-kv \
  --name dc-domain-admin-password \
  --value "YOUR_SECURE_PASSWORD"

# DSRM password
az keyvault secret set --vault-name dc-promotion-kv \
  --name dc-dsrm-password \
  --value "YOUR_DSRM_PASSWORD"

# ServiceNow token (optional)
az keyvault secret set --vault-name dc-promotion-kv \
  --name servicenow-token \
  --value "YOUR_TOKEN"

# Teams webhook (optional)
az keyvault secret set --vault-name dc-promotion-kv \
  --name teams-webhook-url \
  --value "YOUR_WEBHOOK_URL"
```

## Step 4: Create Azure AD App Registration

```bash
# Create app registration
az ad app create \
  --display-name "GitHub-DC-Promotion-Pipeline"
```

Note the `appId` from the output.

## Step 5: Configure OIDC Federated Credentials

For **staging** environment:

```bash
az ad app federated-credential create \
  --id <APP_ID> \
  --parameters '{
    "name": "GitHub-Staging",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:environment:staging",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

For **production** environment:

```bash
az ad app federated-credential create \
  --id <APP_ID> \
  --parameters '{
    "name": "GitHub-Production",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:environment:production",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

## Step 6: Grant Key Vault Access

```bash
# Get the app's object ID
APP_OBJECT_ID=$(az ad sp show --id <APP_ID> --query id -o tsv)

# Grant Key Vault Secrets User role
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $APP_OBJECT_ID \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-dc-automation/providers/Microsoft.KeyVault/vaults/dc-promotion-kv
```

## Step 7: Configure GitHub Secrets

Add these secrets to your GitHub repository:

1. **AZURE_CLIENT_ID**: App ID from Step 4
2. **AZURE_TENANT_ID**: Your Azure AD tenant ID
3. **AZURE_SUBSCRIPTION_ID**: Your Azure subscription ID
4. **KEY_VAULT_NAME**: `dc-promotion-kv`

### Adding secrets via GitHub UI:
1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add each secret

### Adding secrets via GitHub CLI:
```bash
gh secret set AZURE_CLIENT_ID --body "<APP_ID>"
gh secret set AZURE_TENANT_ID --body "<TENANT_ID>"
gh secret set AZURE_SUBSCRIPTION_ID --body "<SUBSCRIPTION_ID>"
gh secret set KEY_VAULT_NAME --body "dc-promotion-kv"
```

## Step 8: Test OIDC Authentication

```bash
# Test from GitHub Actions workflow
az login --service-principal \
  -u $AZURE_CLIENT_ID \
  -t $AZURE_TENANT_ID \
  --federated-token $(cat $ACTIONS_ID_TOKEN_REQUEST_TOKEN)
```

## Verification Checklist

- [ ] Resource group created
- [ ] Key Vault created with RBAC enabled
- [ ] All required secrets stored in Key Vault
- [ ] App registration created
- [ ] Federated credentials configured for staging and production
- [ ] Key Vault access granted to app
- [ ] GitHub secrets configured
- [ ] OIDC authentication tested

## Security Best Practices

1. **Least Privilege**: Only grant necessary permissions
2. **Separate Environments**: Use different Key Vaults for staging/production
3. **Secret Rotation**: Rotate secrets regularly
4. **Audit Logging**: Enable Key Vault diagnostic logs
5. **Network Security**: Consider using Private Endpoints

## Troubleshooting

### Issue: "Federated credential not found"
- Verify the subject identifier matches your repo/environment exactly
- Check issuer URL is correct

### Issue: "Access denied to Key Vault"
- Verify RBAC role assignment
- Check app has correct permissions
- Ensure federated credential is active

### Issue: "Secret not found"
- Verify secret names match exactly
- Check secret is not disabled
- Ensure app has Secrets User role

## Next Steps

- [GitHub Actions Setup](GITHUB-ACTIONS-SETUP.md)
- Return to [Main README](../README.md)
