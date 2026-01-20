#!/bin/bash
# Quick script to start DC01 lab VM

echo "🚀 Starting DC01 lab environment..."
az vm start --resource-group VAMDEVTEST --name DC01 --no-wait

echo ""
echo "⏳ Checking status..."
sleep 10

az vm show --resource-group VAMDEVTEST --name DC01 --show-details \
  --query "{Name:name, PowerState:powerState, PrivateIP:privateIps, PublicIP:publicIps}" \
  -o table

echo ""
echo "✅ DC01 Lab Environment"
echo "   Public IP: 4.234.159.63"
echo "   Private IP: 10.0.0.6"
echo "   Domain: linkedin.local"
echo ""
echo "Next: Wait 2-3 minutes for Windows to fully boot, then test connectivity:"
echo "  Test-NetConnection 4.234.159.63 -Port 5985"
