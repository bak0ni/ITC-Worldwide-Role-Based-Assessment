
#Install Microsoft Graph PowerShell module (if not already installed):
Install-Module Microsoft.Graph -Scope CurrentUser

#Connect to Microsoft Graph with required scopes:
Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory", "Directory.ReadWrite.All"

#Get Role Definition IDs
# List all directory roles and filter for required ones
$roles = Get-MgDirectoryRoleDefinition | Where-Object { 
    $_.DisplayName -in @("Global Administrator", "Security Administrator", "Exchange Administrator", "SharePoint Administrator", "Teams Administrator") 
}

# Show matched roles
$roles | Select-Object DisplayName, Id


#Get usrs object Id
Get-MgUser -UserId "user@domain.com" | Select-Object Id

# Replace with the object ID of the user who should be eligible
$userId = "<user-object-id>"

# Loop through each role and assign it via PIM
foreach ($role in $roles) {
    New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -Action "adminAssign" `
        -DirectoryScopeId "/" `
        -PrincipalId $userId `
        -RoleDefinitionId $role.Id `
        -Justification "Enable PIM for admin roles" `
        -Schedule @{
            StartDateTime = (Get-Date).ToString("o")
            Expiration = @{
                Type = "NoExpiration"
            }
        }
}


