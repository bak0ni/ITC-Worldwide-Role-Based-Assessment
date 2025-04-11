<#
.SYNOPSIS
  Script to enroll Azure Virtual Desktop VMs to Microsoft Intune for endpoint security management.
.DESCRIPTION
  This script performs the following actions:
  1. Installs required PowerShell modules
  2. Connects to Azure and Microsoft Graph
  3. Retrieves all AVD VMs from specified host pools
  4. Enables Intune enrollment prerequisites on AVD VMs
  5. Initiates Intune enrollment on all VMs
  6. Configures endpoint security settings via Intune
.PARAMETER ResourceGroupName
  Name of the resource group containing the AVD host pools
.PARAMETER HostPoolNames
  Array of AVD host pool names to target
.PARAMETER TenantId
  Azure AD tenant ID
.NOTES
  Version:        1.0
  Author:         Your Name
  Creation Date:  2025-04-11
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string[]]$HostPoolNames,
    
    [Parameter(Mandatory = $true)]
    [string]$TenantId
)

# Function to check if module is installed, and install if not
function Install-RequiredModule {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        
        [Parameter(Mandatory = $false)]
        [string]$MinimumVersion
    )
    
    $moduleParams = @{
        Name = $ModuleName
        Force = $true
        ErrorAction = "Stop"
    }
    
    if ($MinimumVersion) {
        $moduleParams.Add("MinimumVersion", $MinimumVersion)
    }
    
    # Check if module is installed with correct version
    $moduleInstalled = Get-Module -ListAvailable -Name $ModuleName
    if (-not $moduleInstalled -or ($MinimumVersion -and ($moduleInstalled.Version -lt [Version]$MinimumVersion))) {
        Write-Host "Installing module $ModuleName..."
        Install-Module @moduleParams
    }
    else {
        Write-Host "Module $ModuleName is already installed."
    }
    
    # Import the module
    Import-Module -Name $ModuleName -Force
}

# Function to connect to Azure and Microsoft Graph
function Connect-ToAzureAndGraph {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )
    
    # Connect to Azure
    $azConnection = Connect-AzAccount -TenantId $TenantId
    
    if (-not $azConnection) {
        throw "Failed to connect to Azure. Please check your credentials and try again."
    }
    
    # Connect to Microsoft Graph with necessary permissions for Intune management
    $graphScopes = @(
        "DeviceManagementConfiguration.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "DeviceManagementServiceConfig.ReadWrite.All"
    )
    
    Connect-MgGraph -Scopes $graphScopes
    
    # Check if connection was successful
    $context = Get-MgContext
    if (-not $context) {
        throw "Failed to connect to Microsoft Graph. Please check your permissions and try again."
    }
}

# Function to get all session hosts from host pools
function Get-AVDSessionHosts {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string[]]$HostPoolNames
    )
    
    $sessionHosts = @()
    
    foreach ($hostPoolName in $HostPoolNames) {
        try {
            Write-Host "Getting session hosts for host pool $hostPoolName..."
            $hostPool = Get-AzWvdHostPool -ResourceGroupName $ResourceGroupName -Name $hostPoolName
            
            if (-not $hostPool) {
                Write-Warning "Host pool $hostPoolName not found in resource group $ResourceGroupName."
                continue
            }
            
            $currentHosts = Get-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -HostPoolName $hostPoolName
            
            foreach ($host in $currentHosts) {
                # Extract the VM name from session host name (e.g., hostpoolname/vmname)
                $vmName = ($host.Name -split '/')[-1]
                $vmName = $vmName.Split('.')[0] # Remove domain suffix if present
                
                $sessionHosts += [PSCustomObject]@{
                    VMName = $vmName
                    SessionHostName = $host.Name
                    ResourceGroupName = $ResourceGroupName
                    HostPoolName = $hostPoolName
                    Status = $host.Status
                }
            }
        }
        catch {
            Write-Error "Error retrieving session hosts for host pool $hostPoolName: $_"
        }
    }
    
    return $sessionHosts
}

# Function to prepare VM for Intune enrollment
function Enable-IntuneEnrollmentPrereqs {
    param (
        [Parameter(Mandatory = $true)]
        [string]$VMName,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )
    
    try {
        # Create script to run on the VM
        $scriptContent = @'
# Enable required services
$servicesToEnable = @(
    "WinRM",
    "WinHttpAutoProxySvc",
    "DmEnrollmentSvc",
    "DmWapPushService"
)

foreach ($service in $servicesToEnable) {
    Set-Service -Name $service -StartupType Automatic
    Start-Service -Name $service -ErrorAction SilentlyContinue
}

# Enable required registry settings
$registrySettings = @{
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MDM" = @{
        "TenantId" = ""  # Will be populated during actual enrollment
        "AutoEnrollmentEnabled" = 1
    }
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM" = @{
        "AutoEnrollMDM" = 1
        "UseAADCredentialType" = 1
    }
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" = @{
        "DisableWindowsConsumerFeatures" = 0
    }
}

foreach ($path in $registrySettings.Keys) {
    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    
    foreach ($name in $registrySettings[$path].Keys) {
        $value = $registrySettings[$path][$name]
        New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWORD -Force | Out-Null
    }
}

# Ensure the Intune Management Extension is installed
$intuneManagementExtensionPath = "$env:ProgramFiles\Microsoft Intune\Microsoft Intune Management Extension"
if (!(Test-Path $intuneManagementExtensionPath)) {
    # Create directory to store installer
    $downloadPath = "$env:TEMP\IntuneManagementExtension"
    if (!(Test-Path $downloadPath)) {
        New-Item -Path $downloadPath -ItemType Directory -Force | Out-Null
    }
    
    # Download Intune Management Extension
    $url = "https://aka.ms/intunemanagementextension"
    $outputFile = "$downloadPath\IntuneManagementExtension.msi"
    Invoke-WebRequest -Uri $url -OutFile $outputFile
    
    # Install the extension
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$outputFile`" /qn" -Wait
}

# Enable automatic device enrollment via scheduled task
$taskName = "Schedule created by enrollment client for automatically enrolling in MDM from AAD"
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if (!$taskExists) {
    $action = New-ScheduledTaskAction -Execute "deviceenroller.exe" -Argument "/c /AutoEnrollMDM"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal
}

# Enable Hybrid Azure AD Join via GPO
$gpoSettings = @{
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin" = @{
        "autoWorkplaceJoin" = 1
    }
}

foreach ($path in $gpoSettings.Keys) {
    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    
    foreach ($name in $gpoSettings[$path].Keys) {
        $value = $gpoSettings[$path][$name]
        New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWORD -Force | Out-Null
    }
}

# Force a restart of Intune-related services
Restart-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue
gpupdate /force

# Create marker file to indicate script has run
$markerFile = "$env:ProgramData\IntuneEnrollmentPrereqsComplete.txt"
Set-Content -Path $markerFile -Value "Intune enrollment prerequisites completed on $(Get-Date)"

Write-Output "Intune enrollment prerequisites have been configured successfully."
'@

        # Save script to local file
        $localScriptPath = "$env:TEMP\Enable-IntuneEnrollmentPrereqs.ps1"
        Set-Content -Path $localScriptPath -Value $scriptContent -Force
        
        # Upload and execute script on the VM
        Write-Host "Running Intune prerequisites script on VM $VMName..."
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId 'RunPowerShellScript' -ScriptPath $localScriptPath
        
        # Check result
        if ($result.Status -eq "Succeeded") {
            Write-Host "Successfully configured Intune prerequisites on VM $VMName" -ForegroundColor Green
            return $true
        }
        else {
            Write-Warning "Failed to configure Intune prerequisites on VM $VMName: $($result.Error)"
            return $false
        }
    }
    catch {
        Write-Error "Error configuring VM $VMName for Intune enrollment: $_"
        return $false
    }
    finally {
        # Clean up local script file
        if (Test-Path $localScriptPath) {
            Remove-Item -Path $localScriptPath -Force
        }
    }
}

# Function to trigger Intune enrollment
function Start-IntuneEnrollment {
    param (
        [Parameter(Mandatory = $true)]
        [string]$VMName,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )
    
    try {
        # Create script to run on the VM
        $enrollmentScript = @"
# Get Azure AD Join information
`$tenantId = "$TenantId"

# Ensure proper MDM enrollment settings
`$mdmRegPath = "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\MDM"
if (!(Test-Path `$mdmRegPath)) {
    New-Item -Path `$mdmRegPath -Force | Out-Null
}
Set-ItemProperty -Path `$mdmRegPath -Name "TenantId" -Value `$tenantId -Type String -Force

# Force enrollment through scheduled task invocation
`$taskName = "Schedule created by enrollment client for automatically enrolling in MDM from AAD"
if (Get-ScheduledTask -TaskName `$taskName -ErrorAction SilentlyContinue) {
    Start-ScheduledTask -TaskName `$taskName
    Write-Output "Triggered MDM enrollment task."
} else {
    # Alternate method if the scheduled task doesn't exist
    Start-Process -FilePath "deviceenroller.exe" -ArgumentList "/c /AutoEnrollMDM" -NoNewWindow
    Write-Output "Manually triggered MDM enrollment."
}

# Force Azure AD sync and device registration
dsregcmd.exe /join

# Wait for enrollment to complete (up to 5 minutes)
`$maxWaitTime = 300 # 5 minutes
`$startTime = Get-Date
`$enrolled = `$false

do {
    `$enrollmentStatus = dsregcmd.exe /status
    
    if (`$enrollmentStatus -match "AzureAdJoined : YES" -and `$enrollmentStatus -match "DomainJoined : YES" -and `$enrollmentStatus -match "DeviceId : " -and `$enrollmentStatus -notmatch "DeviceId : \s*$") {
        Write-Output "Device successfully enrolled."
        `$enrolled = `$true
        break
    }
    
    Start-Sleep -Seconds 30
    `$currentTime = Get-Date
    `$elapsedTime = (`$currentTime - `$startTime).TotalSeconds
    
    Write-Output "Waiting for enrollment to complete... (`$([int]`$elapsedTime) seconds elapsed)"
} while (`$elapsedTime -lt `$maxWaitTime)

if (-not `$enrolled) {
    Write-Warning "Enrollment did not complete within the timeout period. Please check enrollment status manually."
}

# Get detailed enrollment status
`$enrollmentStatus = dsregcmd.exe /status
Write-Output "`nEnrollment Status:"
Write-Output `$enrollmentStatus

# Create marker file to indicate enrollment was attempted
`$markerFile = "`$env:ProgramData\IntuneEnrollmentAttempt.txt"
Set-Content -Path `$markerFile -Value "Enrollment attempted on `$(Get-Date)`nStatus: `$(if(`$enrolled){"Success"}else{"Timeout"})"

# Restart the Intune Management Extension to pick up enrollment
Restart-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue
"@

        # Save script to local file
        $localEnrollmentScriptPath = "$env:TEMP\Start-IntuneEnrollment.ps1"
        Set-Content -Path $localEnrollmentScriptPath -Value $enrollmentScript -Force
        
        # Upload and execute script on the VM
        Write-Host "Initiating Intune enrollment on VM $VMName..."
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $VMName -CommandId 'RunPowerShellScript' -ScriptPath $localEnrollmentScriptPath
        
        # Check result
        if ($result.Status -eq "Succeeded") {
            Write-Host "Successfully initiated Intune enrollment on VM $VMName" -ForegroundColor Green
            Write-Host "Enrollment output: $($result.Value[0].Message)"
            return $true
        }
        else {
            Write-Warning "Failed to initiate Intune enrollment on VM $VMName: $($result.Error)"
            return $false
        }
    }
    catch {
        Write-Error "Error enrolling VM $VMName to Intune: $_"
        return $false
    }
    finally {
        # Clean up local script file
        if (Test-Path $localEnrollmentScriptPath) {
            Remove-Item -Path $localEnrollmentScriptPath -Force
        }
    }
}

# Function to configure baseline security settings via Intune
function Set-IntuneBaselineSecuritySettings {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$TargetGroupNames
    )
    
    try {
        Write-Host "Configuring Intune baseline security policies for AVD VMs..."
        
        # Get target groups
        $targetGroups = @()
        foreach ($groupName in $TargetGroupNames) {
            $group = Get-MgGroup -Filter "displayName eq '$groupName'"
            if ($group) {
                $targetGroups += $group.Id
            }
            else {
                Write-Warning "Group '$groupName' not found in Azure AD."
            }
        }
        
        if ($targetGroups.Count -eq 0) {
            Write-Warning "No valid target groups found. Cannot create Intune policies."
            return $false
        }
        
        # Create Endpoint Security Policies
        
        # 1. Windows Security Baseline
        $securityBaselineDisplayName = "AVD VMs - Windows Security Baseline"
        
        # Using Graph API to create security baseline (as there's no direct cmdlet)
        $securityBaselineUri = "https://graph.microsoft.com/beta/deviceManagement/templates"
        
        # Get available templates
        $templates = Invoke-MgGraphRequest -Uri $securityBaselineUri -Method GET
        
        # Find the latest Windows 11 security baseline template
        $win11Template = $templates.value | Where-Object { 
            $_.displayName -like "*Windows 11*" -and $_.displayName -like "*security baseline*" 
        } | Sort-Object -Property @{Expression = {[Version]::new(($_.displayName -replace '.*?(\d+\.\d+\.\d+).*', '$1'))}; Descending = $true} | Select-Object -First 1
        
        if ($win11Template) {
            # Create policy from template
            $securityBaselineBody = @{
                displayName = $securityBaselineDisplayName
                description = "Security baseline for AVD VMs"
                templateId = $win11Template.id
                assignments = @(
                    @{
                        target = @{
                            "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                            groupId = $targetGroups[0]
                        }
                    }
                )
            } | ConvertTo-Json -Depth 10
            
            # Create the policy
            $createdBaseline = Invoke-MgGraphRequest -Uri "$securityBaselineUri/$($win11Template.id)/createInstance" -Method POST -Body $securityBaselineBody -ContentType "application/json"
            
            Write-Host "Created Windows Security Baseline: $securityBaselineDisplayName" -ForegroundColor Green
        }
        else {
            Write-Warning "Could not find Windows 11 security baseline template."
        }
        
        # 2. Endpoint Detection and Response Policy
        $edrPolicyDisplayName = "AVD VMs - Endpoint Detection and Response"
        
        $edrPolicy = @{
            "@odata.type" = "#microsoft.graph.windowsDefenderAdvancedThreatProtectionConfiguration"
            displayName = $edrPolicyDisplayName
            description = "Configures Microsoft Defender for Endpoint for AVD VMs"
            allowSampleSharing = $true
            enableExpeditedTelemetryReporting = $true
            advancedThreatProtectionOnboardingFilename = "WindowsDefenderATP.onboarding"
            assignments = @(
                @{
                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId = $targetGroups[0]
                    }
                }
            )
        } | ConvertTo-Json -Depth 10
        
        $edrPolicyUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
        $createdEdrPolicy = Invoke-MgGraphRequest -Uri $edrPolicyUri -Method POST -Body $edrPolicy -ContentType "application/json"
        
        Write-Host "Created Endpoint Detection and Response Policy: $edrPolicyDisplayName" -ForegroundColor Green
        
        # 3. Antivirus Policy
        $avPolicyDisplayName = "AVD VMs - Antivirus Policy"
        
        $avPolicy = @{
            "@odata.type" = "#microsoft.graph.windowsDefenderAntivirusConfiguration"
            displayName = $avPolicyDisplayName
            description = "Configures Windows Defender Antivirus for AVD VMs"
            allowRealtimeMonitoring = $true
            enableNetworkProtection = "enable"
            enableLowCpuPriority = $true
            enableCloudProtection = $true
            enableScanArchiveFiles = $true
            enableEmailScanning = $true
            enableScriptScanning = $true
            daysToRetainCleanedMalware = 30
            realTimeScanDirection = "bothDirections"
            scanParameter = "fullScan"
            scheduledScanTime = "120"
            assignments = @(
                @{
                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId = $targetGroups[0]
                    }
                }
            )
        } | ConvertTo-Json -Depth 10
        
        $createdAvPolicy = Invoke-MgGraphRequest -Uri $edrPolicyUri -Method POST -Body $avPolicy -ContentType "application/json"
        
        Write-Host "Created Antivirus Policy: $avPolicyDisplayName" -ForegroundColor Green
        
        # 4. Firewall Policy
        $firewallPolicyDisplayName = "AVD VMs - Firewall Policy"
        
        $firewallPolicy = @{
            "@odata.type" = "#microsoft.graph.windowsFirewallNetworkProfile"
            displayName = $firewallPolicyDisplayName
            description = "Configures Windows Firewall for AVD VMs"
            firewallEnabled = "allowed"
            stealthModeBlocked = $true
            incomingConnectionsBlocked = $true
            outgoingConnectionsRequired = $false
            securedPacketExemptionAllowed = $false
            policyRulesFromGroupPolicyMerged = $true
            globalPortRulesFromGroupPolicyMerged = $true
            connectionSecurityRulesFromGroupPolicyMerged = $true
            inboundNotificationsBlocked = $false
            assignments = @(
                @{
                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId = $targetGroups[0]
                    }
                }
            )
        } | ConvertTo-Json -Depth 10
        
        $createdFirewallPolicy = Invoke-MgGraphRequest -Uri $edrPolicyUri -Method POST -Body $firewallPolicy -ContentType "application/json"
        
        Write-Host "Created Firewall Policy: $firewallPolicyDisplayName" -ForegroundColor Green
        
        # 5. Device Configuration Policy for Local Admin Password Solution
        $localAdminPolicyDisplayName = "AVD VMs - LAPS Configuration"
        
        $localAdminPolicy = @{
            "@odata.type" = "#microsoft.graph.windows10EndpointProtectionConfiguration"
            displayName = $localAdminPolicyDisplayName
            description = "Configures Local Administrator Password Solution for AVD VMs"
            localAdminPasswordManagementEnabled = $true
            passwordExpirationProtectionEnabled = $true
            passwordComplexity = "large"
            passwordLength = 16
            passwordRecoveryEnabled = $true
            maximumPasswordAge = "P60D"
            minimumPasswordAge = "P1D"
            passwordHistoryBlockCount = 24
            assignments = @(
                @{
                    target = @{
                        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                        groupId = $targetGroups[0]
                    }
                }
            )
        } | ConvertTo-Json -Depth 10
        
        $createdLocalAdminPolicy = Invoke-MgGraphRequest -Uri $edrPolicyUri -Method POST -Body $localAdminPolicy -ContentType "application/json"
        
        Write-Host "Created LAPS Policy: $localAdminPolicyDisplayName" -ForegroundColor Green
        
        return $true
    }
    catch {
        Write-Error "Error creating Intune security policies: $_"
        return $false
    }
}

# Main execution script
try {
    # Set execution policy for the current process
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

    # Banner
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "    Azure VDI Intune Enrollment & Security Tool    " -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    
    # Install required modules
    Write-Host "`n[1/5] Installing required PowerShell modules..." -ForegroundColor Yellow
    Install-RequiredModule -ModuleName "Az.Accounts" -MinimumVersion "2.12.0"
    Install-RequiredModule -ModuleName "Az.Resources" -MinimumVersion "6.10.0"
    Install-RequiredModule -ModuleName "Az.Compute" -MinimumVersion "5.10.0"
    Install-RequiredModule -ModuleName "Az.DesktopVirtualization" -MinimumVersion "3.1.0"
    Install-RequiredModule -ModuleName "Microsoft.Graph" -MinimumVersion "2.0.0"
    
    # Connect to Azure and Graph
    Write-Host "`n[2/5] Connecting to Azure and Microsoft Graph..." -ForegroundColor Yellow
    Connect-ToAzureAndGraph -TenantId $TenantId
    
    # Get all session hosts
    Write-Host "`n[3/5] Retrieving AVD session hosts..." -ForegroundColor Yellow
    $sessionHosts = Get-AVDSessionHosts -ResourceGroupName $ResourceGroupName -HostPoolNames $HostPoolNames
    
    if ($sessionHosts.Count -eq 0) {
        throw "No session hosts found in the specified host pools."
    }
    
    Write-Host "Found $($sessionHosts.Count) session hosts across $($HostPoolNames.Count) host pools."
    
    # Create an Azure AD security group for the VDI VMs if needed
    Write-Host "`n[4/5] Creating/verifying Azure AD security group for VDI VMs..." -ForegroundColor Yellow
    $vdiGroupName = "AVD-VDI-Intune-Managed"
    
    # Check if group exists
    $vdiGroup = Get-MgGroup -Filter "displayName eq '$vdiGroupName'"
    
    if (-not $vdiGroup) {
        Write-Host "Creating security group: $vdiGroupName"
        $vdiGroup = New-MgGroup -DisplayName $vdiGroupName -Description "AVD VDI VMs managed by Intune" -SecurityEnabled $true -MailEnabled $false -MailNickname "AVD-VDI-Intune-Managed"
    }
    else {
        Write-Host "Security group $vdiGroupName already exists."
    }
    
    # Process each VM
    Write-Host "`n[5/5] Processing VMs for Intune enrollment..." -ForegroundColor Yellow
    
    $successCount = 0
    $failureCount = 0
    
    foreach ($host in $sessionHosts) {
        Write-Host "`nProcessing VM: $($host.VMName) from host pool $($host.HostPoolName)..." -ForegroundColor Cyan
        
        # Step 1: Enable Intune enrollment prerequisites
        $prereqsSuccess = Enable-IntuneEnrollmentPrereqs -VMName $host.VMName -ResourceGroupName $ResourceGroupName
        
        if (-not $prereqsSuccess) {
            Write-Warning "Failed to enable Intune enrollment prerequisites on VM $($host.VMName). Skipping to next VM."
            $failureCount++
            continue
        }
        
        # Step 2: Trigger Intune enrollment
        $enrollmentSuccess = Start-IntuneEnrollment -VMName $host.VMName -ResourceGroupName $ResourceGroupName -TenantId $TenantId
        
        if ($enrollmentSuccess) {
            Write-Host "Successfully initiated Intune enrollment on VM $($host.VMName)" -ForegroundColor Green
            $successCount++
        }
        else {
            Write-Warning "Failed to initiate Intune enrollment on VM $($host.VMName)"
            $failureCount++
        }
        
        # Add a short delay between VMs to avoid throttling
        Start-Sleep -Seconds 5
    }
    
    # Configure security policies if there were successful enrollments
    if ($successCount -gt 0) {
        Write-Host "`nConfiguring Intune security policies for enrolled VMs..." -ForegroundColor Yellow
        $policiesConfigured = Set-IntuneBaselineSecuritySettings -TargetGroupNames @($vdiGroupName)
        
        if ($policiesConfigured) {
            Write-Host "Successfully configured Intune security policies for AVD VMs." -ForegroundColor Green
        }
        else {
            Write-Warning "Failed to configure some Intune security policies."
        }
    }
    
    # Summary
    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host "                  Summary                         " -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "Total VMs processed:   $($sessionHosts.Count)" -ForegroundColor White
    Write-Host "Successful enrollments: $successCount" -ForegroundColor Green
    Write-Host "Failed enrollments:     $failureCount" -ForegroundColor Red
    Write-Host "`nIntune security policies configured for Azure AD group: $vdiGroupName" -ForegroundColor White
    Write-Host "=================================================" -ForegroundColor Cyan
    
    Write-Host "`nNote: Full enrollment may take up to 1 hour to complete and for devices to appear in Intune."
    Write-Host "Check the Intune portal to verify device enrollment status and policy application."
}
catch {
    Write-Error "An error occurred during execution: $_"
    exit 1
}