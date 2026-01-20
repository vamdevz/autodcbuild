#!/bin/bash
# Azure AD App Registration Setup for GitHub Actions OIDC
# Run this script to create the App Registration and get CLIENT_ID

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Azure AD App Registration Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get current Azure account info
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "✅ Tenant ID: $TENANT_ID"
echo "✅ Subscription ID: $SUBSCRIPTION_ID"
echo ""

# Prompt for GitHub repo details
read -p "Enter your GitHub organization/username: " GITHUB_ORG
read -p "Enter your GitHub repository name: " GITHUB_REPO

APP_NAME="github-actions-dc-pipeline"

echo ""
echo "Creating Azure AD App Registration: $APP_NAME"
echo ""

# Create App Registration
APP_ID=$(az ad app create \
  --display-name "$APP_NAME" \
  --query appId -o tsv)

echo "✅ App Registration created!"
echo "   App (Client) ID: $APP_ID"
echo ""

# Get Object ID
OBJECT_ID=$(az ad app show --id $APP_ID --query id -o tsv)

# Create Service Principal
SP_ID=$(az ad sp create --id $APP_ID --query id -o tsv)
echo "✅ Service Principal created"
echo ""

# Wait for propagation
echo "⏳ Waiting for Azure AD propagation (10 seconds)..."
sleep 10

# Create federated credentials for GitHub OIDC - Lab environment
echo "Creating federated credential for lab environment..."
az ad app federated-credential create \
  --id $OBJECT_ID \
  --parameters "{
    \"name\": \"github-lab-env\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:lab\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" > /dev/null

echo "✅ Federated credential created for lab environment"

# Grant Key Vault access
echo ""
echo "Granting Key Vault access to App..."
az keyvault set-policy \
  --name kv-dclab-0119 \
  --object-id $SP_ID \
  --secret-permissions get list > /dev/null

echo "✅ Key Vault access granted"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SETUP COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Add these secrets to your GitHub repository:"
echo "   (Settings → Secrets and variables → Actions → New repository secret)"
echo ""
echo "AZURE_CLIENT_ID = $APP_ID"
echo "AZURE_TENANT_ID = $TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
echo "KEY_VAULT_NAME = kv-dclab-0119"
echo ""
echo "✅ GitHub OIDC is now configured for lab environment"
echo ""
