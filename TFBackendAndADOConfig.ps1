# Ensure required PowerShell modules are installed and imported
# Install-Module -Name Az -AllowClobber -Scope CurrentUser
# Install-Module -Name Az.DevOps -Scope CurrentUser
# Import-Module Az
# Import-Module Az.DevOps

# Login to Azure
Connect-AzAccount

# Variables
$resourceGroupDev = "terraform-state-development-rg"
$resourceGroupProd = "terraform-state-production-rg"
$storageAccountDev = "tfstatedevelopmentsa"
$storageAccountProd = "tfstateproductionsa"
$containerName = "tfstate"
$location = "France Central" 

# Create Resource Groups
New-AzResourceGroup -Name $resourceGroupDev -Location $location
New-AzResourceGroup -Name $resourceGroupProd -Location $location

# Create Storage Accounts
New-AzStorageAccount -ResourceGroupName $resourceGroupDev -Name $storageAccountDev -Location $location -SkuName Standard_LRS -Kind StorageV2
New-AzStorageAccount -ResourceGroupName $resourceGroupProd -Name $storageAccountProd -Location $location -SkuName Standard_LRS -Kind StorageV2

# Get Storage Account Keys and Create Containers
$storageAccountDevKeys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupDev -Name $storageAccountDev
$storageAccountProdKeys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupProd -Name $storageAccountProd

$contextDev = New-AzStorageContext -StorageAccountName $storageAccountDev -StorageAccountKey $storageAccountDevKeys[0].Value
$contextProd = New-AzStorageContext -StorageAccountName $storageAccountProd -StorageAccountKey $storageAccountProdKeys[0].Value

New-AzStorageContainer -Name $containerName -Context $contextDev
New-AzStorageContainer -Name $containerName -Context $contextProd

# Azure DevOps Configuration
# Login to Azure DevOps
Connect-AzAccount # Ensure you are logged in to Azure DevOps

# Set Azure DevOps organization and project
#Assuming ITC Worldwide for Org and Zero Trust Multi-Domain Network for Project
$organizationUrl = "https://dev.azure.com/itcworldwide"
$projectName = "Zero Trust Multi-Domain Network"

# Set the organization
Set-AzDevOpsOrganization -Organization $organizationUrl

# Create Service Connections
$servicePrincipalIdDev = "SP_ID_Dev" # Replace with service principal ID for development
$servicePrincipalKeyDev = "SP_KEY_Dev" # Replace with service principal key for development
$tenantId = "TENANT_ID" # Replace with tenant ID
$subscriptionIdDev = "SUBSCRIPTION_ID_Dev" # Replace with subscription ID for development
$subscriptionNameDev = "SubscriptionNameDev" # Replace with subscription name for development

New-AzDevOpsServiceEndpointAzureRm -Name "development-service-connection" `
    -ServicePrincipalId $servicePrincipalIdDev `
    -ServicePrincipalKey $servicePrincipalKeyDev `
    -TenantId $tenantId `
    -SubscriptionId $subscriptionIdDev `
    -SubscriptionName $subscriptionNameDev `
    -ProjectName $projectName

$servicePrincipalIdProd = "SP_ID_Prod" # Replace with service principal ID for production
$servicePrincipalKeyProd = "SP_KEY_Prod" # Replace with service principal key for production
$subscriptionIdProd = "SUBSCRIPTION_ID_Prod" # Replace with subscription ID for production
$subscriptionNameProd = "SubscriptionNameProd" # Replace with subscription name for production

New-AzDevOpsServiceEndpointAzureRm -Name "production-service-connection" `
    -ServicePrincipalId $servicePrincipalIdProd `
    -ServicePrincipalKey $servicePrincipalKeyProd `
    -TenantId $tenantId `
    -SubscriptionId $subscriptionIdProd `
    -SubscriptionName $subscriptionNameProd `
    -ProjectName $projectName

# Create Variable Groups
$devVariables = @{
    API_KEY = "key_value_dev"
    PASSWORD = "password_value_dev"
}

$prodVariables = @{
    API_KEY = "key_value_prod"
    PASSWORD = "password_value_prod"
}

New-AzDevOpsVariableGroup -Name "terraform-secrets-development" `
    -Variables $devVariables `
    -ProjectName $projectName

New-AzDevOpsVariableGroup -Name "terraform-secrets-production" `
    -Variables $prodVariables `
    -ProjectName $projectName