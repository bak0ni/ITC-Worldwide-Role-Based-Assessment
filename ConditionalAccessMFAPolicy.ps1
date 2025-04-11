function New-MFAConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Creates a conditional access policy that enforces MFA for all users except a breakglass account and requires admin roles to re-authenticate with MFA every 2 hours.
    
    .DESCRIPTION
        This function creates a conditional access policy in Azure AD using Microsoft Graph API.
        The policy enforces MFA for all users except a specified breakglass account.
        Additionally, it requires users with admin roles to re-authenticate with MFA every 2 hours.
    
    .PARAMETER PolicyName
        The name of the conditional access policy to create.
    
    .PARAMETER BreakglassUPN
        The UserPrincipalName of the breakglass account that will be excluded from MFA.
    
    .PARAMETER TenantId
        The Azure AD tenant ID. If not specified, the function will use the currently connected tenant.
    
    .PARAMETER ClientId
        The Application (client) ID of the app registration with Microsoft Graph permissions.
    
    .PARAMETER ClientSecret
        The client secret of the app registration.
    
    .EXAMPLE
        New-MFAConditionalAccessPolicy -PolicyName "MFA for All Users - Admin Re-auth" -BreakglassUPN "breakglass@contoso.com" -ClientId "12345678-1234-1234-1234-123456789012" -ClientSecret "your-client-secret"
    
    .NOTES
        Required Microsoft Graph permissions:
        - Policy.ReadWrite.ConditionalAccess
        - Application.Read.All
        - Directory.Read.All
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$PolicyName,
        
        [Parameter(Mandatory=$true)]
        [string]$BreakglassUPN,
        
        [Parameter(Mandatory=$false)]
        [string]$TenantId,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientId,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientSecret
    )
    
    # Connect to Microsoft Graph
    function Connect-MsGraph {
        param (
            [string]$TenantId,
            [string]$ClientId,
            [string]$ClientSecret
        )
        
        $tenantParam = if ($TenantId) { $TenantId } else { "common" }
        $tokenUrl = "https://login.microsoftonline.com/$tenantParam/oauth2/v2.0/token"
        
        $body = @{
            client_id     = $ClientId
            scope         = "https://graph.microsoft.com/.default"
            client_secret = $ClientSecret
            grant_type    = "client_credentials"
        }
        
        try {
            $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
            return $tokenResponse.access_token
        }
        catch {
            Write-Error "Failed to acquire token: $_"
            throw
        }
    }
    
    function Invoke-MsGraphRequest {
        param (
            [string]$AccessToken,
            [string]$Uri,
            [string]$Method = "GET",
            [object]$Body = $null,
            [string]$ContentType = "application/json"
        )
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "Content-Type"  = $ContentType
        }
        
        $params = @{
            Uri         = $Uri
            Headers     = $headers
            Method      = $Method
        }
        
        if ($Body -and $Method -ne "GET") {
            $params.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 }
        }
        
        try {
            return Invoke-RestMethod @params
        }
        catch {
            Write-Error "Graph API request failed: $_"
            throw
        }
    }
    
    # Get the breakglass user by UPN
    function Get-AzureADUser {
        param (
            [string]$AccessToken,
            [string]$UserPrincipalName
        )
        
        $uri = "https://graph.microsoft.com/v1.0/users?`$filter=userPrincipalName eq '$UserPrincipalName'"
        $response = Invoke-MsGraphRequest -AccessToken $AccessToken -Uri $uri
        
        if ($response.value.Count -eq 0) {
            throw "User with UPN '$UserPrincipalName' not found"
        }
        
        return $response.value[0]
    }
    
    # Get all directory roles
    function Get-AdminRoles {
        param (
            [string]$AccessToken
        )
        
        $uri = "https://graph.microsoft.com/v1.0/directoryRoles"
        $response = Invoke-MsGraphRequest -AccessToken $AccessToken -Uri $uri
        
        return $response.value
    }
    
    # Main execution
    try {
        Write-Verbose "Connecting to Microsoft Graph API..."
        $accessToken = Connect-MsGraph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        
        Write-Verbose "Getting breakglass user information..."
        $breakglassUser = Get-AzureADUser -AccessToken $accessToken -UserPrincipalName $BreakglassUPN
        
        Write-Verbose "Getting admin roles..."
        $adminRoles = Get-AdminRoles -AccessToken $accessToken
        $adminRoleIds = $adminRoles | ForEach-Object { $_.id }
        
        # Construct the conditional access policy
        $policyBody = @{
            displayName = $PolicyName
            state = "enabled"
            conditions = @{
                users = @{
                    includeUsers = @("All")
                    excludeUsers = @($breakglassUser.id)
                    includeGroups = @()
                    excludeGroups = @()
                    includeRoles = @()
                    excludeRoles = @()
                }
                applications = @{
                    includeApplications = @("All")
                    excludeApplications = @()
                }
                clientAppTypes = @("browser", "mobileAppsAndDesktopClients")
                locations = @{
                    includeLocations = @("All")
                    excludeLocations = @()
                }
            }
            grantControls = @{
                operator = "OR"
                builtInControls = @("mfa")
            }
        }
        
        Write-Verbose "Creating base MFA policy for all users except breakglass account..."
        $createPolicyUri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
        $basePolicy = Invoke-MsGraphRequest -AccessToken $accessToken -Uri $createPolicyUri -Method "POST" -Body $policyBody
        
        Write-Verbose "Base policy created with ID: $($basePolicy.id)"
        
        # Create the admin re-authentication policy
        $adminPolicyBody = @{
            displayName = "$PolicyName - Admin Role Re-Authentication"
            state = "enabled"
            conditions = @{
                users = @{
                    includeUsers = @("All")
                    excludeUsers = @($breakglassUser.id)
                    includeGroups = @()
                    excludeGroups = @()
                    includeRoles = $adminRoleIds
                    excludeRoles = @()
                }
                applications = @{
                    includeApplications = @("All")
                    excludeApplications = @()
                }
                clientAppTypes = @("browser", "mobileAppsAndDesktopClients")
                locations = @{
                    includeLocations = @("All")
                    excludeLocations = @()
                }
            }
            grantControls = @{
                operator = "OR"
                builtInControls = @("mfa")
                authenticationStrength = @{
                    id = "00000000-0000-0000-0000-000000000002" # Standard MFA strength
                }
            }
            sessionControls = @{
                signInFrequency = @{
                    value = 2
                    type = "hours"
                    isEnabled = $true
                }
                persistentBrowser = @{
                    mode = "never"
                    isEnabled = $true
                }
            }
        }
        
        Write-Verbose "Creating admin re-authentication policy..."
        $adminPolicy = Invoke-MsGraphRequest -AccessToken $accessToken -Uri $createPolicyUri -Method "POST" -Body $adminPolicyBody
        
        Write-Verbose "Admin policy created with ID: $($adminPolicy.id)"
        
        return @{
            BasePolicy = $basePolicy
            AdminPolicy = $adminPolicy
        }
    }
    catch {
        Write-Error "Failed to create conditional access policies: $_"
        throw
    }
}

function Update-MFAConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Updates an existing conditional access policy.
    
    .DESCRIPTION
        This function updates an existing conditional access policy in Azure AD using Microsoft Graph API.
    
    .PARAMETER PolicyId
        The ID of the policy to update.
    
    .PARAMETER PolicyName
        The new name for the policy (optional).
    
    .PARAMETER State
        The state of the policy: "enabled", "disabled", or "enabledForReportingButNotEnforced".
    
    .PARAMETER TenantId
        The Azure AD tenant ID. If not specified, the function will use the currently connected tenant.
    
    .PARAMETER ClientId
        The Application (client) ID of the app registration with Microsoft Graph permissions.
    
    .PARAMETER ClientSecret
        The client secret of the app registration.
    
    .EXAMPLE
        Update-MFAConditionalAccessPolicy -PolicyId "00000000-0000-0000-0000-000000000000" -State "disabled" -ClientId "12345678-1234-1234-1234-123456789012" -ClientSecret "your-client-secret"
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$PolicyId,
        
        [Parameter(Mandatory=$false)]
        [string]$PolicyName,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("enabled", "disabled", "enabledForReportingButNotEnforced")]
        [string]$State,
        
        [Parameter(Mandatory=$false)]
        [string]$TenantId,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientId,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientSecret
    )
    
    try {
        # Connect to Microsoft Graph
        $tenantParam = if ($TenantId) { $TenantId } else { "common" }
        $tokenUrl = "https://login.microsoftonline.com/$tenantParam/oauth2/v2.0/token"
        
        $body = @{
            client_id     = $ClientId
            scope         = "https://graph.microsoft.com/.default"
            client_secret = $ClientSecret
            grant_type    = "client_credentials"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        $accessToken = $tokenResponse.access_token
        
        # Get current policy
        $getPolicyUri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$PolicyId"
        $headers = @{
            "Authorization" = "Bearer $accessToken"
            "Content-Type"  = "application/json"
        }
        
        $currentPolicy = Invoke-RestMethod -Uri $getPolicyUri -Headers $headers -Method GET
        
        # Update policy properties
        $updateRequired = $false
        
        if ($PolicyName) {
            $currentPolicy.displayName = $PolicyName
            $updateRequired = $true
        }
        
        if ($State) {
            $currentPolicy.state = $State
            $updateRequired = $true
        }
        
        if ($updateRequired) {
            # Update the policy
            $updatePolicyUri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$PolicyId"
            $updatedPolicy = Invoke-RestMethod -Uri $updatePolicyUri -Headers $headers -Method PATCH -Body ($currentPolicy | ConvertTo-Json -Depth 20)
            
            Write-Verbose "Policy updated successfully"
            return $updatedPolicy
        } else {
            Write-Verbose "No changes to apply"
            return $currentPolicy
        }
    }
    catch {
        Write-Error "Failed to update conditional access policy: $_"
        throw
    }
}

function Remove-MFAConditionalAccessPolicy {
    <#
    .SYNOPSIS
        Removes a conditional access policy.
    
    .DESCRIPTION
        This function removes an existing conditional access policy in Azure AD using Microsoft Graph API.
    
    .PARAMETER PolicyId
        The ID of the policy to remove.
    
    .PARAMETER TenantId
        The Azure AD tenant ID. If not specified, the function will use the currently connected tenant.
    
    .PARAMETER ClientId
        The Application (client) ID of the app registration with Microsoft Graph permissions.
    
    .PARAMETER ClientSecret
        The client secret of the app registration.
    
    .EXAMPLE
        Remove-MFAConditionalAccessPolicy -PolicyId "00000000-0000-0000-0000-000000000000" -ClientId "12345678-1234-1234-1234-123456789012" -ClientSecret "your-client-secret"
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$PolicyId,
        
        [Parameter(Mandatory=$false)]
        [string]$TenantId,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientId,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientSecret
    )
    
    try {
        # Connect to Microsoft Graph
        $tenantParam = if ($TenantId) { $TenantId } else { "common" }
        $tokenUrl = "https://login.microsoftonline.com/$tenantParam/oauth2/v2.0/token"
        
        $body = @{
            client_id     = $ClientId
            scope         = "https://graph.microsoft.com/.default"
            client_secret = $ClientSecret
            grant_type    = "client_credentials"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        $accessToken = $tokenResponse.access_token
        
        # Delete the policy
        $deletePolicyUri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$PolicyId"
        $headers = @{
            "Authorization" = "Bearer $accessToken"
        }
        
        Invoke-RestMethod -Uri $deletePolicyUri -Headers $headers -Method DELETE
        
        Write-Verbose "Policy deleted successfully"
        return $true
    }
    catch {
        Write-Error "Failed to delete conditional access policy: $_"
        throw
    }
}

Export-ModuleMember -Function New-MFAConditionalAccessPolicy, Update-MFAConditionalAccessPolicy, Remove-MFAConditionalAccessPolicy