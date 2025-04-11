# variables.tf

variable "resource_group_name" {
  description = "Name of the existing resource group where VNets are deployed"
  type        = string
}

variable "selected_vnets" {
  description = "List of VNets to deploy AVD in"
  type        = list(string)
  default     = ["frc-pyt-vnet", "uks-dotnet-vnet"] # Example: Change as needed
}

variable "subnet_cidr_blocks" {
  description = "CIDR blocks for AVD subnets in each VNet"
  type        = map(string)
  default = {
    "frc-pyt-vnet"    = "10.1.10.0/24"
    "frc-dotnet-vnet" = "10.2.10.0/24"
    "frc-game-vnet"   = "10.3.10.0/24"
    "frc-spec-vnet"   = "10.4.10.0/24"
    "itn-pyt-vnet"    = "10.5.10.0/24"
    "itn-dotnet-vnet" = "10.6.10.0/24"
    "itn-game-vnet"   = "10.7.10.0/24"
    "itn-spec-vnet"   = "10.8.10.0/24"
    "uks-pyt-vnet"    = "10.9.10.0/24"
    "uks-dotnet-vnet" = "10.10.10.0/24"
    "uks-game-vnet"   = "10.11.10.0/24"
    "uks-spec-vnet"   = "10.12.10.0/24"
  }
}

variable "workspace_name" {
  description = "Name of the AVD workspace"
  type        = string
  default     = "avd-workspace"
}

variable "workspace_friendly_name" {
  description = "Friendly name of the AVD workspace"
  type        = string
  default     = "AVD Workspace"
}

variable "hostpool_name" {
  description = "Name of the AVD host pool"
  type        = string
  default     = "avd-hostpool"
}

variable "hostpool_friendly_name" {
  description = "Friendly name of the AVD host pool"
  type        = string
  default     = "AVD Host Pool"
}

variable "company_name" {
  description = "Company name for resource naming"
  type        = string
  default     = "Contoso"
}

variable "vm_size" {
  description = "Size of the AVD VMs"
  type        = string
  default     = "Standard_D4s_v5" # 4 vCPU, 16 GB RAM
}

variable "initial_instance_count" {
  description = "Initial number of VM instances in each scale set"
  type        = number
  default     = 2
}

variable "admin_username" {
  description = "Admin username for AVD VMs"
  type        = string
  default     = "avdadmin"
  sensitive   = true
}

variable "admin_password" {
  description = "Admin password for AVD VMs"
  type        = string
  sensitive   = true
}

variable "assigned_users" {
  description = "List of Azure AD object IDs for users who should be assigned to the AVD application group"
  type        = list(string)
  default     = [] # Add Azure AD Object IDs here
}

variable "tags" {
  description = "Tags to apply to AVD resources"
  type        = map(string)
  default = {
    Environment = "Production"
    Workload    = "VirtualDesktop"
  }
}
