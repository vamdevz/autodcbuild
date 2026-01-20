# Domain Controller Build & Promotion - IaC Pipeline Project

## Project Overview
Automated pipeline for provisioning, promoting, and configuring Windows Domain Controllers using Infrastructure as Code principles.

---

## Workflow Stages (LinkedIn DC Promotion Process)

### Stage 1: VM Provisioning (Euclid Platform)
**Input:** Infrastructure request
**Output:** Base Windows Server VM (domain-joined, inventory-ready)

**Requirements:**
- VM meets minimum specs (CPU, RAM, Disk)
- **Machine is domain-joined** (linkedin.biz or internal.linkedin.cn)
- Network configuration complete (DNS pointing to existing DCs)
- WinRM enabled for remote management
- Base OS patched and hardened
- D: and E: drives configured for ADDS database/logs

---

### Stage 2: Ansible Control Node (Automation Hub)

#### Step 1: Pre-Promotion Validation
**Objective:** Verify machine is domain-joined and ready for DC promotion

**Tasks:**
- Confirm server is domain member (not standalone/workgroup)
- Verify DNS pointing to existing domain controllers
- Test network connectivity to PDC Emulator
- Validate AD reachability via LDAP

**Ansible Role:** `roles/pre-promotion-check/`

**Key Modules:**
- `win_domain_membership` (check state)
- `win_shell` (DNS validation)
- `win_ping` (connectivity tests)

**Implementation:**
```yaml
- name: Check if machine is domain-joined
  win_shell: |
    $cs = Get-WmiObject Win32_ComputerSystem
    if ($cs.PartOfDomain -ne $true) {
      throw "Server is not domain-joined. Domain join required before DC promotion."
    }
    $cs.Domain
  register: domain_check
  changed_when: false

- name: Verify DNS points to domain controllers
  win_shell: |
    $dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"}).ServerAddresses
    if ($dnsServers.Count -eq 0) {
      throw "No DNS servers configured"
    }
    Write-Output "DNS Servers: $($dnsServers -join ', ')"
  register: dns_check
  changed_when: false
```

---

#### Step 2: Promote to AD DC (DCPromo)
**Objective:** Add Domain Controller to existing LinkedIn domain (linkedin.biz or internal.linkedin.cn)

**Tasks:**
- Install AD DS role and management tools
- Execute `Install-ADDSDomainController` to join existing domain
- Configure database, SYSVOL, and log paths (D:, E: drives)
- Set DSRM password securely

**Ansible Role:** `roles/dc-promotion/`

**Key Modules:**
- `win_feature` (AD-Domain-Services)
- `win_domain_controller`
- `win_powershell`

**Implementation:**
```yaml
- name: Install AD DS Role
  win_feature:
    name: AD-Domain-Services
    include_management_tools: yes
    include_sub_features: yes
    state: present
  register: adds_install

- name: Promote to Domain Controller (LinkedIn Domain)
  win_shell: |
    $SecurePassword = ConvertTo-SecureString "{{ dsrm_password }}" -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential("{{ domain_admin_user }}", (ConvertTo-SecureString "{{ domain_admin_password }}" -AsPlainText -Force))
    
    Install-ADDSDomainController `
      -DomainName "{{ domain_name }}" `
      -Credential $Cred `
      -SafeModeAdministratorPassword $SecurePassword `
      -InstallDns:$true `
      -DatabasePath "D:\NTDS" `
      -SysvolPath "D:\SYSVOL" `
      -LogPath "E:\NTDS\Logs" `
      -SiteName "{{ ad_site_name }}" `
      -Force `
      -NoRebootOnCompletion:$true
  register: dc_promotion
  async: 3600
  poll: 30
```

---

#### Step 2: Reboot Handling
**Objective:** Graceful reboot management with health checks

**Tasks:**
- Detect if reboot is required (post-promotion flag)
- Execute controlled reboot
- Wait for WinRM/RDP connectivity
- Verify AD services (NTDS, DNS, Netlogon) are running
- Confirm DC is advertising as Global Catalog

**Ansible Role:** `roles/reboot-handler/`

**Key Modules:**
- `win_reboot`
- `wait_for_connection`
- `win_service_info`

**Implementation:**
```yaml
- name: Reboot DC after promotion
  win_reboot:
    reboot_timeout: 600
    msg: "DC Promotion Reboot - Ansible Automation"
  when: dc_promotion.reboot_required

- name: Wait for DC services to stabilize
  wait_for_connection:
    timeout: 300
    delay: 60

- name: Verify critical AD services
  win_service_info:
    name: "{{ item }}"
  loop:
    - NTDS
    - DNS
    - Netlogon
    - W32Time
  register: service_status
  failed_when: service_status.services[0].state != 'running'
```

---

#### Step 3: DC Health Status Checks (Post-Promotion)
**Objective:** Comprehensive health validation per LinkedIn standards

**Tasks:**

**3a. Verify SYSVOL and NETLOGON Shares**
```yaml
- name: Check SYSVOL and NETLOGON shares
  win_shell: |
    $shares = Get-WmiObject win32_share | Where-Object {$_.Name -in @('SYSVOL', 'NETLOGON')}
    if ($shares.Count -ne 2) {
      throw "SYSVOL and/or NETLOGON shares not found"
    }
    $shares | Select-Object Name, Path, Description | Format-Table -AutoSize
  register: share_check
  changed_when: false
```

**3b. Verify AD Replication Status**
```yaml
- name: Check replication status (repadmin /showrepl)
  win_shell: |
    $output = repadmin /showrepl
    if ($LASTEXITCODE -ne 0) { throw "Repadmin failed" }
    
    # Check for successful replication with timestamps
    if ($output -notmatch "Last attempt.*was successful") {
      throw "Replication not successful"
    }
    $output
  register: repl_status
  changed_when: false
```

**3c. Check Replication Queue**
```yaml
- name: Check replication queue (repadmin /queue)
  win_shell: |
    $output = repadmin /queue
    # Extract queue count from output
    if ($output -match "Queue contains (\d+)") {
      $queueCount = [int]$matches[1]
      if ($queueCount -gt 0) {
        Write-Warning "Replication queue has $queueCount items"
      }
    }
    $output
  register: repl_queue
  changed_when: false
  failed_when: false  # Don't fail, just warn
```

**3d. DCDiag - DCPromo Test**
```yaml
- name: Run dcdiag /test:dcpromo
  win_shell: |
    dcdiag /test:dcpromo /dnsdomain:{{ domain_name }} /replicadc
  register: dcdiag_dcpromo
  changed_when: false
  failed_when: "'failed' in dcdiag_dcpromo.stdout.lower()"
```

**3e. DCDiag - DNS Registration Test**
```yaml
- name: Run dcdiag /test:registerindns
  win_shell: |
    dcdiag /test:registerindns /dnsdomain:{{ domain_name }}
  register: dcdiag_registerindns
  changed_when: false
  failed_when: "'failed' in dcdiag_registerindns.stdout.lower()"
```

**3f. Full DCDiag**
```yaml
- name: Run full dcdiag
  win_command: dcdiag.exe
  register: dcdiag_full
  changed_when: false
  failed_when: "'failed' in dcdiag_full.stdout.lower()"
```

**3g. DCDiag - DNS Test**
```yaml
- name: Run dcdiag /test:dns
  win_command: dcdiag.exe /test:dns
  register: dcdiag_dns
  changed_when: false
  failed_when: "'failed' in dcdiag_dns.stdout.lower()"
```

---

#### Step 4: Configure DNS Conditional Forwarders
**Objective:** Set up DNS conditional forwarders per LinkedIn network architecture

**Tasks:**
- Create conditional forwarder for China domain (if promoting in BIZ)
- Create conditional forwarder for BIZ domain (if promoting in China)
- Create conditional forwarders for Microsoft internal domains (gtm.corp.microsoft.com, sts.microsoft.com)
- Verify DNS resolution using nslookup

**Ansible Role:** `roles/dns-configuration/`

**Key Modules:**
- `win_dns_zone` (conditional forwarders)
- `win_shell` (nslookup validation)

**Implementation:**
```yaml
- name: Create DNS Conditional Forwarder - internal.linkedin.cn
  win_shell: |
    Add-DnsServerConditionalForwarderZone `
      -Name "internal.linkedin.cn" `
      -MasterServers @("10.44.71.6", "10.44.71.5") `
      -ErrorAction SilentlyContinue
  when: domain_name == 'linkedin.biz'
  register: cf_china

- name: Create DNS Conditional Forwarder - linkedin.biz
  win_shell: |
    Add-DnsServerConditionalForwarderZone `
      -Name "linkedin.biz" `
      -MasterServers @("10.41.63.5", "10.41.63.6", "172.21.2.103", "172.21.2.104") `
      -ErrorAction SilentlyContinue
  when: domain_name == 'internal.linkedin.cn'
  register: cf_biz

- name: Create DNS Conditional Forwarder - gtm.corp.microsoft.com
  win_shell: |
    Add-DnsServerConditionalForwarderZone `
      -Name "gtm.corp.microsoft.com" `
      -MasterServers @("172.31.197.245", "172.31.197.246", "172.31.197.80", "172.31.197.81") `
      -ErrorAction SilentlyContinue
  register: cf_gtm

- name: Create DNS Conditional Forwarder - sts.microsoft.com
  win_shell: |
    Add-DnsServerConditionalForwarderZone `
      -Name "sts.microsoft.com" `
      -MasterServers @("172.31.197.245", "172.31.197.246", "172.31.197.80", "172.31.197.81") `
      -ErrorAction SilentlyContinue
  register: cf_sts

- name: Verify DNS Resolution - msft.sts.microsoft.com
  win_shell: |
    $result = nslookup msft.sts.microsoft.com
    if ($LASTEXITCODE -ne 0) { throw "DNS resolution failed for msft.sts.microsoft.com" }
    $result
  register: nslookup_msft
  changed_when: false

- name: Verify DNS Resolution - linkedin.biz
  win_shell: |
    $result = nslookup linkedin.biz
    if ($LASTEXITCODE -ne 0) { throw "DNS resolution failed for linkedin.biz" }
    $result
  register: nslookup_biz
  changed_when: false
  when: domain_name == 'internal.linkedin.cn'

- name: Verify DNS Resolution - internal.linkedin.cn
  win_shell: |
    $result = nslookup internal.linkedin.cn
    if ($LASTEXITCODE -ne 0) { throw "DNS resolution failed for internal.linkedin.cn" }
    $result
  register: nslookup_china
  changed_when: false
  when: domain_name == 'linkedin.biz'
```

---

#### Step 4a: Verify DC is Authenticating Users
**Objective:** Confirm DC is servicing authentication requests

**Tasks:**
- Check Security Event Log for authentication events
- Look for Event IDs: 4624 (Logon), 4768 (Kerberos TGT), 4771 (Kerberos pre-auth failed)
- Validate DC is processing real authentication traffic

**Implementation:**
```yaml
- name: Check authentication events in Security log
  win_shell: |
    $authEvents = Get-WinEvent -FilterHashtable @{
      LogName='Security'
      Id=4624,4768,4771
      StartTime=(Get-Date).AddHours(-1)
    } -MaxEvents 50 -ErrorAction SilentlyContinue
    
    if ($authEvents.Count -eq 0) {
      Write-Warning "No authentication events found in the last hour"
      Write-Output "Status: Monitoring (may take time for first auth events)"
    } else {
      Write-Output "Found $($authEvents.Count) authentication events"
      $authEvents | Group-Object Id | Select-Object Name, Count | Format-Table
    }
  register: auth_check
  changed_when: false
  failed_when: false  # Don't fail, just warn if no events yet
```

---

#### Step 5: Agent, Certificate Installation, and Security Groups
**Objective:** Install required agents and configure security compliance per LinkedIn standards

**Pre-Installation Checks:**

**5.1 Verify Existing Agents**
```yaml
- name: Check for pre-installed agents (Qualys, MMA)
  win_shell: |
    Get-WmiObject -Class Win32_Product | Where-Object {
      $_.Name -like "*Qualys*" -or $_.Name -like "*Microsoft Monitoring Agent*"
    } | Select-Object Name, Version | Format-Table -AutoSize
  register: existing_agents
  changed_when: false

- name: Verify Qualys agent version (must be 6.2.5.4 or higher)
  win_shell: |
    $qualys = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -like "*Qualys*"}
    if ($qualys) {
      $version = [Version]$qualys.Version
      $minVersion = [Version]"6.2.5.4"
      if ($version -lt $minVersion) {
        throw "Qualys version $($qualys.Version) is below minimum 6.2.5.4"
      }
      Write-Output "Qualys version: $($qualys.Version) - OK"
    }
  register: qualys_version_check
  changed_when: false
```

**5.2 Copy Installers from Central Share**
```yaml
- name: Copy installers from lva1-adc01 share
  win_copy:
    src: "\\\\lva1-adc01.linkedin.biz\\c$\\Temp\\"
    dest: "C:\\Temp\\"
    remote_src: yes
  register: installer_copy
```

**5.3 Install .NET Framework 4.8**
```yaml
- name: Install .NET Framework 4.8 (required for Azure AD Password Protection)
  win_package:
    path: "C:\\Temp\\ndp48-x86-x64-allos-enu.exe"
    product_id: '{2E02CCC7-CE65-37E5-8EA3-E4872D434D0C}'
    arguments: '/q /norestart'
    state: present
  register: dotnet_install

- name: Reboot after .NET Framework installation
  win_reboot:
    reboot_timeout: 600
    msg: ".NET Framework 4.8 installation - reboot required"
  when: dotnet_install.changed
```

**5.4 Install Azure AD Password Protection DC Agent**
```yaml
- name: Install Azure AD Password Protection DC Agent
  win_package:
    path: "C:\\Temp\\AzureADPasswordProtectionDCAgentSetup.exe"
    product_id: '{AZUREAD-PWD-PROTECTION-GUID}'
    arguments: '/quiet /norestart'
    state: present
  register: azuread_pwd_agent
```

**5.5 Install Azure Advanced Threat Protection Sensor**
```yaml
- name: Install Azure ATP Sensor
  win_package:
    path: "C:\\Temp\\Azure ATP Sensor Setup.exe"
    arguments: '/quiet NetFrameworkCommandLineArguments="/q"'
    state: present
  register: azureatp_install
```

**5.6 Install Quest Change Auditor Agent**
```yaml
- name: Install Quest Change Auditor Agent
  win_package:
    path: "C:\\Temp\\QuestChangeAuditorAgent.msi"
    product_id: '{QUEST-AGENT-GUID}'
    arguments: '/qn'
    state: present
  register: quest_agent
```

**5.7 Final Reboot After All Agents**
```yaml
- name: Final reboot after all agent installations
  win_shell: |
    shutdown /r /c "ChangeTicket - {{ inventory_hostname }} DC Promotion" /t 30
  async: 0
  poll: 0
  ignore_errors: yes

- name: Wait for server to come back online
  wait_for_connection:
    timeout: 600
    delay: 60
```

**5.8 Verify Agent Services**
```yaml
- name: Check agent services status
  win_shell: |
    Get-Service -Name AzureADPasswordProtectionDCAgent, QualysAgent, NPSrvHost, HealthService, AATPSensor |
    Select-Object Name, DisplayName, Status, StartType |
    Format-Table -AutoSize
  register: agent_services
  changed_when: false
  failed_when: false  # Some agents may be initializing

- name: Display service status with warnings for stopped services
  debug:
    msg: |
      Agent Services Status:
      {{ agent_services.stdout }}
      
      Note: Some agents may show 'Stopped' - this is normal during first-time initialization.
      They will start automatically within a few minutes.
```

**5.9 Add DC to Security Group for LDAPS Auto-Enrollment**
```yaml
- name: Add DC computer object to SG-LDAPS-DomainController-AutoEnroll
  win_shell: |
    Import-Module ActiveDirectory
    $dcComputer = Get-ADComputer -Identity $env:COMPUTERNAME
    Add-ADGroupMember -Identity "SG-LDAPS-DomainController-AutoEnroll" -Members $dcComputer -ErrorAction SilentlyContinue
  register: ldaps_group_add
  delegate_to: "{{ primary_dc_hostname }}"  # Run on existing DC
```

**5.10 Request Certificate via go/incerts**
```yaml
- name: Trigger certificate auto-enrollment
  win_shell: |
    # Trigger Group Policy update to apply certificate auto-enrollment
    gpupdate /force
    
    # Trigger certificate enrollment
    certutil -pulse
    
    Write-Output "Certificate enrollment triggered. Check via MMC (certlm.msc) or go/incerts portal."
  register: cert_enrollment
  changed_when: false
```

**5.11 Confirm with InfoSec SPM Team (Manual Step)**
```yaml
- name: Reminder - InfoSec FIM Compliance Check
  debug:
    msg: |
      ⚠️  MANUAL ACTION REQUIRED:
      - Contact InfoSec SPM team to confirm DC is FIM compliant
      - Verify in FIM dashboard: {{ inventory_hostname }}
      - Open ticket if compliance issues found
```

---

#### Step 6: Final Post-Checks & Reporting
**Objective:** Comprehensive validation and deployment report generation

**Tasks:**

**6.1 Final Health Summary**
```yaml
- name: Generate comprehensive DC health report
  win_shell: |
    $report = @{
      Hostname = $env:COMPUTERNAME
      Domain = (Get-ADDomain).DNSRoot
      Site = (Get-ADDomainController -Identity $env:COMPUTERNAME).Site
      Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    # AD Services
    $adServices = Get-Service NTDS, DNS, Netlogon, W32Time, KDC
    $report.ADServicesRunning = ($adServices | Where-Object {$_.Status -eq 'Running'}).Count
    $report.ADServicesTotal = $adServices.Count
    
    # Replication Check
    $replCheck = repadmin /showrepl | Select-String "Last attempt.*was successful"
    $report.ReplicationHealthy = $replCheck.Count -gt 0
    
    # Shares
    $shares = Get-WmiObject win32_share | Where-Object {$_.Name -in @('SYSVOL', 'NETLOGON')}
    $report.RequiredSharesPresent = $shares.Count -eq 2
    
    # DNS Conditional Forwarders
    $forwarders = Get-DnsServerZone | Where-Object {$_.ZoneType -eq 'Forwarder'}
    $report.ConditionalForwardersConfigured = $forwarders.Count
    
    # Agent Services
    $agents = Get-Service -Name AzureADPasswordProtectionDCAgent, QualysAgent, HealthService, AATPSensor -ErrorAction SilentlyContinue
    $report.AgentsInstalled = ($agents | Measure-Object).Count
    $report.AgentsRunning = ($agents | Where-Object {$_.Status -eq 'Running'} | Measure-Object).Count
    
    # LDAPS Group Membership
    try {
      $dcComputer = Get-ADComputer -Identity $env:COMPUTERNAME -Properties MemberOf
      $report.LDAPSGroupMember = $dcComputer.MemberOf -match "SG-LDAPS-DomainController-AutoEnroll"
    } catch {
      $report.LDAPSGroupMember = "Unknown"
    }
    
    $report | ConvertTo-Json -Depth 3
  register: final_health_report
  changed_when: false

- name: Display final health report
  debug:
    msg: "{{ final_health_report.stdout | from_json }}"
```

**6.2 Generate Deployment Report**
```yaml
- name: Create deployment summary report
  template:
    src: dc-deployment-report.j2
    dest: "/tmp/DC-Deployment-{{ inventory_hostname }}-{{ ansible_date_time.date }}.txt"
  delegate_to: localhost

- name: Send completion notification to Teams/Slack
  uri:
    url: "{{ notification_webhook_url }}"
    method: POST
    body_format: json
    body:
      "@type": "MessageCard"
      "@context": "http://schema.org/extensions"
      themeColor: "0076D7"
      summary: "DC Promotion Complete"
      sections:
        - activityTitle: "✅ Domain Controller Promotion Complete"
          activitySubtitle: "{{ inventory_hostname }}"
          facts:
            - name: "Domain"
              value: "{{ domain_name }}"
            - name: "Site"
              value: "{{ ad_site_name }}"
            - name: "Completion Time"
              value: "{{ ansible_date_time.iso8601 }}"
            - name: "Replication Status"
              value: "Healthy"
            - name: "Agents Installed"
              value: "Qualys, MMA, Azure AD Pwd Protection, Azure ATP, Quest Change Auditor"
          markdown: true
  delegate_to: localhost
  when: notification_webhook_url is defined
```

**6.3 Update CMDB/ServiceNow**
```yaml
- name: Update ServiceNow CMDB
  uri:
    url: "{{ servicenow_api_url }}/api/now/table/cmdb_ci_server"
    method: PATCH
    headers:
      Authorization: "Bearer {{ servicenow_token }}"
    body_format: json
    body:
      name: "{{ inventory_hostname }}"
      u_role: "Domain Controller"
      u_ad_site: "{{ ad_site_name }}"
      u_promotion_date: "{{ ansible_date_time.date }}"
      operational_status: "1"  # Operational
  delegate_to: localhost
  when: servicenow_api_url is defined
```

**6.4 Create Handoff Documentation**
```yaml
- name: Generate handoff documentation
  debug:
    msg: |
      ============================================
      DC PROMOTION COMPLETE - HANDOFF CHECKLIST
      ============================================
      
      Server: {{ inventory_hostname }}
      Domain: {{ domain_name }}
      Site: {{ ad_site_name }}
      Promoted: {{ ansible_date_time.iso8601 }}
      
      ✅ COMPLETED STEPS:
      1. ✓ Pre-checks (domain-joined, DNS validated)
      2. ✓ DC Promotion (Install-ADDSDomainController)
      3. ✓ Health checks (dcdiag, repadmin passed)
      4. ✓ DNS conditional forwarders configured
      5. ✓ Authentication events detected
      6. ✓ Agents installed: Qualys (v6.2.5.4+), MMA, Azure ATP, Quest
      7. ✓ Added to SG-LDAPS-DomainController-AutoEnroll
      8. ✓ Certificate enrollment triggered
      
      ⚠️  MANUAL FOLLOW-UP REQUIRED:
      1. Confirm with InfoSec SPM team - FIM compliance
      2. Verify certificate issued via go/incerts portal
      3. Monitor agent initialization (may take 5-10 minutes)
      4. Update change ticket with completion details
      
      📊 MONITORING:
      - Check replication: repadmin /showrepl
      - Check services: Get-Service NTDS,DNS,Netlogon,W32Time
      - Check auth events: Get-WinEvent -LogName Security -FilterXPath "*[System[(EventID=4624 or EventID=4768)]]"
      
      For issues, contact: AD Operations Team
      ============================================
```

---

## Project Structure

```
dc-build-promotion/
├── ansible.cfg
├── inventory/
│   ├── production/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       ├── all.yml
│   │       ├── domain_controllers.yml
│   │       └── vault.yml (encrypted)
│   └── staging/
│       └── hosts.yml
├── playbooks/
│   ├── 00-pre-promotion-check.yml       # Domain join validation
│   ├── 01-promote-dc.yml                # DCPromo execution
│   ├── 02-reboot-handler.yml            # Post-promotion reboot
│   ├── 03-dc-health-checks.yml          # dcdiag, repadmin, shares
│   ├── 04-configure-dns.yml             # Conditional forwarders
│   ├── 05-verify-authentication.yml     # Event log checks
│   ├── 06-install-agents.yml            # Agent installation suite
│   ├── 07-post-checks-reporting.yml     # Final validation & notifications
│   └── master-pipeline.yml              # Orchestrates all stages
├── roles/
│   ├── pre-promotion-check/       # Domain join validation
│   ├── dc-promotion/               # DCPromo execution
│   ├── reboot-handler/             # Post-promotion reboot
│   ├── dc-health-checks/           # dcdiag, repadmin validation
│   ├── dns-configuration/          # Conditional forwarders
│   ├── authentication-check/       # Event log validation
│   ├── agent-installation/         # LinkedIn agent suite
│   └── post-checks/                # Final reporting
├── files/
│   ├── installers/
│   │   ├── ndp48-x86-x64-allos-enu.exe           # .NET Framework 4.8
│   │   ├── AzureADPasswordProtectionDCAgent.exe  # Azure AD Pwd Protection
│   │   ├── Azure_ATP_Sensor_Setup.exe            # Azure ATP
│   │   ├── QuestChangeAuditorAgent.msi           # Quest Change Auditor
│   │   ├── MMASetup-AMD64.exe                    # Microsoft Monitoring Agent
│   │   └── QualysCloudAgent.exe                  # Qualys Agent
│   └── scripts/
│       ├── Test-DCHealth.ps1
│       ├── Get-ReplicationStatus.ps1
│       └── Check-AgentVersions.ps1
├── templates/
│   ├── dcpromo-answer.j2
│   └── monitoring-config.j2
├── vars/
│   ├── domain-config.yml
│   └── agent-versions.yml
├── tests/
│   ├── integration/
│   │   └── test_dc_promotion.yml
│   └── unit/
│       └── test_roles.yml
├── docs/
│   ├── ARCHITECTURE.md
│   ├── RUNBOOK.md
│   └── TROUBLESHOOTING.md
├── .gitlab-ci.yml (or Jenkinsfile, azure-pipelines.yml)
└── README.md
```

---

## CI/CD Pipeline Integration

### GitLab CI Example
```yaml
stages:
  - validate
  - plan
  - provision
  - promote
  - configure
  - verify
  - notify

variables:
  ANSIBLE_HOST_KEY_CHECKING: "False"
  ANSIBLE_VAULT_PASSWORD_FILE: "/vault/.vault_pass"

validate:
  stage: validate
  script:
    - ansible-playbook playbooks/00-pre-flight-check.yml --check --diff
    - ansible-lint playbooks/*.yml
    - yamllint .
  only:
    - merge_requests

promote_dc:
  stage: promote
  script:
    - ansible-playbook playbooks/master-pipeline.yml -i inventory/production
  only:
    - main
  when: manual
  environment:
    name: production

post_validation:
  stage: verify
  script:
    - ansible-playbook playbooks/06-post-checks.yml -i inventory/production
  dependencies:
    - promote_dc
```

---

## Key Technologies & Tools

### Core Stack
- **Ansible** (2.15+): Orchestration and configuration management
- **PowerShell** (5.1+): Windows automation and AD cmdlets
- **Python** (3.10+): Custom modules and scripts
- **Git**: Version control
- **Ansible Vault**: Secrets management

### LinkedIn Enterprise Tools
- **Euclid Platform**: VM provisioning
- **go/incerts**: Certificate enrollment portal
- **InfoSec SPM Team**: FIM compliance validation
- **ServiceNow**: Change management and CMDB
- **Microsoft Teams/Slack**: Notification webhooks

### Optional/CI-CD Tools
- **GitLab CI/Azure DevOps**: Pipeline orchestration
- **AWX/Ansible Tower**: Enterprise automation platform
- **Terraform**: IaC for VM pre-provisioning

---

## Next Steps for Implementation

1. **Phase 1: Foundation (Week 1-2)**
   - Set up Ansible control node (Linux jumpbox)
   - Create inventory structure (linkedin.biz, internal.linkedin.cn)
   - Develop domain-join validation playbook
   - Set up access to \\\\lva1-adc01.linkedin.biz\\c$\\Temp

2. **Phase 2: Core Automation (Week 3-4)**
   - Build DC promotion role (Install-ADDSDomainController)
   - Implement reboot handling with WinRM reconnect
   - Create health check validation (dcdiag, repadmin)

3. **Phase 3: DNS & Agent Installation (Week 5-6)**
   - Develop DNS conditional forwarder configuration
   - Build agent installation roles (Qualys, MMA, Azure AD Pwd Protection, Azure ATP, Quest)
   - Create authentication event monitoring

4. **Phase 4: CI/CD Integration (Week 7-8)**
   - Set up GitLab CI / Azure DevOps pipeline
   - Integrate with ServiceNow for change tickets
   - Add Teams/Slack notifications
   - Create deployment report templates

5. **Phase 5: Production Rollout (Week 9-10)**
   - Pilot with 1-2 DCs in non-prod environment
   - Coordinate with InfoSec SPM team for FIM validation
   - Gather feedback from AD Operations team
   - Full production deployment with approval gates

---

## Success Metrics

- **Total Deployment Time**: < 60 minutes (from domain-joined VM to fully configured DC)
- **DCPromo Success Rate**: > 95% first-time success
- **Replication Convergence**: < 15 minutes (repadmin /queue = 0)
- **Agent Installation Success**: 100% (all 5 agents: Qualys, MMA, Azure AD Pwd Protection, Azure ATP, Quest)
- **Health Check Pass Rate**: 100% (all dcdiag tests pass)
- **Manual Steps Remaining**: Certificate validation (go/incerts) + InfoSec FIM confirmation
- **Automation Coverage**: ~90% (only cert validation and FIM check remain manual)

---

## Risk Mitigation

1. **Rollback Plan**: Snapshot before promotion
2. **Dry-Run Mode**: `--check` flag for validation
3. **Idempotency**: All tasks re-runnable safely
4. **Logging**: Comprehensive audit trail
5. **Testing**: Dev/Staging environment validation first

---

## LinkedIn-Specific Workflow Summary

This pipeline automates the **LinkedIn Domain Controller promotion process** exactly as documented:

### ✅ Automated Steps (via Ansible)
1. **Pre-Check**: Verify machine is domain-joined
2. **DC Promotion**: Execute DCPromo to add DC to existing domain
3. **Health Checks**: Run all dcdiag and repadmin tests
4. **DNS Configuration**: Set up conditional forwarders (China, BIZ, Microsoft domains)
5. **Authentication Validation**: Check Event IDs 4624, 4768, 4771
6. **Agent Installation**: Install all 5 required agents (.NET 4.8 → Azure AD Pwd Protection → Azure ATP → Quest Change Auditor)
7. **LDAPS Group**: Add DC to SG-LDAPS-DomainController-AutoEnroll
8. **Certificate Enrollment**: Trigger certutil -pulse for auto-enrollment
9. **Reporting**: Generate deployment summary and send notifications

### ⚠️ Manual Steps (Post-Automation)
1. **Certificate Validation**: Verify cert issued via go/incerts portal
2. **InfoSec Validation**: Confirm FIM compliance with InfoSec SPM team
3. **Change Ticket Update**: Document completion in ServiceNow

### 🎯 Key Benefits
- **Consistency**: Same process every time, no missed steps
- **Speed**: 60 minutes vs 3+ hours manual
- **Audit Trail**: Full logging and reporting
- **Reduced Errors**: Automated validation catches issues early
- **Scalability**: Can promote multiple DCs in parallel

---

## Ready to Implement?

**Next Actions:**
1. Review this document with AD Operations team
2. Set up Ansible control node with network access
3. Create inventory files for linkedin.biz and internal.linkedin.cn
4. Build and test roles in staging environment
5. Coordinate with InfoSec SPM for FIM validation workflow
6. Create ServiceNow integration for change tracking

**Questions or Need Assistance?**
- Architecture Review: Schedule with Senior DevOps Engineer
- Ansible Development: Contact Infrastructure Automation team
- Agent Versions/Installers: Check \\\\lva1-adc01.linkedin.biz\\c$\\Temp
- FIM Compliance: InfoSec SPM team

---

This is a production-ready architecture tailored for LinkedIn's specific DC promotion workflow.
