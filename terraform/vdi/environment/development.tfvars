# terraform.tfvars
resource_group_name = "existing-rg-name"

# Select which VNets to deploy AVD in (modify as needed)
selected_vnets = [
  "frc-pyt-vnet",    # France Python VNet
  "uks-dotnet-vnet"  # UK .NET VNet
]

# Customize workspace and hostpool names
workspace_name = "enterprise-avd-workspace"
workspace_friendly_name = "Enterprise AVD Workspace"
hostpool_name = "enterprise-avd-hostpool"
hostpool_friendly_name = "Enterprise AVD Host Pool"

# Company information
company_name = "ITC Worldwide"

# VM configuration
vm_size = "Standard_D4s_v5"
initial_instance_count = 2

# Admin credentials (store these securely, preferably in Azure Key Vault)
admin_username = "avdadmin"
admin_password = "REPLACE_WITH_SECURE_PASSWORD"

# Assign users to the AVD application group (Azure AD Object IDs)
assigned_users = [
  # "00000000-0000-0000-0000-000000000000",  # Example User 1
  # "11111111-1111-1111-1111-111111111111"   # Example User 2
]

# Resource tags
tags = {
  Environment = "Production"
  Workload    = "VirtualDesktop"
  Department  = "IT"
  CostCenter  = "12345"
}
