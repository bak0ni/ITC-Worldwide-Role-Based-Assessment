# Azure Virtual Desktop (AVD) with Autoscaling

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.9.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {}

data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "selected_vnets" {
  for_each            = toset(var.selected_vnets)
  name                = each.value
  resource_group_name = data.azurerm_resource_group.existing.name
}

# Create Subnet in each selected VNet for AVD
resource "azurerm_subnet" "avd_subnet" {
  for_each             = data.azurerm_virtual_network.selected_vnets
  name                 = "${each.key}-avd-subnet"
  resource_group_name  = data.azurerm_resource_group.existing.name
  virtual_network_name = each.value.name
  address_prefixes     = [var.subnet_cidr_blocks[each.key]]
}

# Create Network Security Group for AVD
resource "azurerm_network_security_group" "avd_nsg" {
  name                = "avd-nsg"
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name

  security_rule {
    name                       = "AllowRDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

# Associate NSG with each AVD subnet
resource "azurerm_subnet_network_security_group_association" "avd_subnet_nsg" {
  for_each                  = azurerm_subnet.avd_subnet
  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.avd_nsg.id
}

# Create AVD Workspace
resource "azurerm_virtual_desktop_workspace" "workspace" {
  name                = var.workspace_name
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  friendly_name       = var.workspace_friendly_name
  description         = "AVD Workspace for ${var.company_name}"
}

# Create AVD Host Pool
resource "azurerm_virtual_desktop_host_pool" "hostpool" {
  name                 = var.hostpool_name
  location             = data.azurerm_resource_group.existing.location
  resource_group_name  = data.azurerm_resource_group.existing.name
  type                 = "Pooled"
  load_balancer_type   = "BreadthFirst"
  friendly_name        = var.hostpool_friendly_name
  description          = "AVD Host Pool for ${var.company_name}"
  validate_environment = false
  maximum_sessions_allowed = 10
  custom_rdp_properties = "audiocapturemode:i:1;audiomode:i:0;drivestoredirect:s:;redirectclipboard:i:1;redirectcomports:i:0;redirectprinters:i:1;redirectsmartcards:i:1;screen mode id:i:2"
}

# Create AVD application group
resource "azurerm_virtual_desktop_application_group" "dag" {
  name                = "${var.hostpool_name}-dag"
  location            = data.azurerm_resource_group.existing.location
  resource_group_name = data.azurerm_resource_group.existing.name
  type                = "Desktop"
  host_pool_id        = azurerm_virtual_desktop_host_pool.hostpool.id
  friendly_name       = "Desktop Application Group"
  description         = "AVD Desktop Application Group"
}

# Associate Application Group with Workspace
resource "azurerm_virtual_desktop_workspace_application_group_association" "ws_dag" {
  workspace_id         = azurerm_virtual_desktop_workspace.workspace.id
  application_group_id = azurerm_virtual_desktop_application_group.dag.id
}

# Create a registration info token for adding VMs to the hostpool
resource "azurerm_virtual_desktop_host_pool_registration_info" "token" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.hostpool.id
  expiration_date = timeadd(timestamp(), "8h")
}

# Create Shared Image Gallery
resource "azurerm_shared_image_gallery" "sig" {
  name                = replace("${var.company_name}AVDGallery", "-", "")
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
  description         = "Shared Image Gallery for AVD"
}

# Create Image Definition
resource "azurerm_shared_image" "avd_image" {
  name                = "avd-image"
  gallery_name        = azurerm_shared_image_gallery.sig.name
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = data.azurerm_resource_group.existing.location
  os_type             = "Windows"
  hyper_v_generation  = "V2"
  
  identifier {
    publisher = var.company_name
    offer     = "WindowsDesktop"
    sku       = "Win11-22H2-Ent"
  }
}

# Create scaling plan with specific working hours using azapi (since terraform doesn't have a native resource for this yet)
resource "azapi_resource" "scaling_plan" {
  type      = "Microsoft.DesktopVirtualization/scalingPlans@2022-02-10-preview"
  name      = "${var.hostpool_name}-scaling-plan"
  location  = data.azurerm_resource_group.existing.location
  parent_id = data.azurerm_resource_group.existing.id
  
  body = jsonencode({
    properties = {
      hostPoolType           = "Pooled"
      friendlyName           = "Working Hours Scaling Plan"
      description            = "Scales during business hours and shuts down outside working hours"
      exclusionTag           = "excludeFromScaling"
      schedules = [
        {
          name                             = "Weekdays"
          daysOfWeek                       = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
          rampUpStartTime                  = {
            hour   = 6
            minute = 45
          }
          peakStartTime                    = {
            hour   = 8
            minute = 0
          }
          rampDownStartTime                = {
            hour   = 15
            minute = 0
          }
          offPeakStartTime                 = {
            hour   = 16
            minute = 15
          }
          rampUpLoadBalancingAlgorithm    = "BreadthFirst"
          rampUpMinimumHostsPct           = 20
          rampUpCapacityThresholdPct      = 60
          peakLoadBalancingAlgorithm      = "BreadthFirst"
          rampDownLoadBalancingAlgorithm  = "DepthFirst"
          rampDownMinimumHostsPct         = 10
          rampDownCapacityThresholdPct    = 90
          rampDownForceLogoffUsers        = true
          rampDownWaitTimeMinutes         = 30
          rampDownNotificationMessage     = "Your session will be logged off in 30 minutes. Please save your work and log off."
          offPeakLoadBalancingAlgorithm   = "DepthFirst"
        }
      ]
      hostPoolReferences = [
        {
          hostPoolArmPath    = azurerm_virtual_desktop_host_pool.hostpool.id
          scalingPlanEnabled = true
        }
      ]
    }
  })
}

# Create VM Scale Set for each selected VNet
resource "azurerm_orchestrated_virtual_machine_scale_set" "avd_vmss" {
  for_each                      = azurerm_subnet.avd_subnet
  name                          = "${each.key}-vmss"
  location                      = data.azurerm_resource_group.existing.location
  resource_group_name           = data.azurerm_resource_group.existing.name
  platform_fault_domain_count   = 1
  single_placement_group        = false
  instances                     = var.initial_instance_count
  
  sku_name                      = var.vm_size
  
  os_profile {
    windows_configuration {
      computer_name_prefix = substr(replace(each.key, "-", ""), 0, 9)
      admin_username       = var.admin_username
      admin_password       = var.admin_password
      provision_vm_agent   = true
    }
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-11"
    sku       = "win11-22h2-ent"
    version   = "latest"
  }
  
  network_interface {
    name    = "avd-nic"
    primary = true
    
    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = each.value.id
    }
  }
  
  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
    disk_size_gb         = 128
  }
  
  extension {
    name                       = "AVDExtension"
    publisher                  = "Microsoft.Powershell"
    type                       = "DSC"
    type_handler_version       = "2.73"
    auto_upgrade_minor_version = true

    settings = jsonencode({
      modulesUrl = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_3-10-2021.zip"
      configurationFunction = "Configuration.ps1\\AddSessionHost"
      properties = {
        hostPoolName = azurerm_virtual_desktop_host_pool.hostpool.name
        registrationInfoToken = azurerm_virtual_desktop_host_pool_registration_info.token.token
        aadJoin = false
      }
    })
  }

  automatic_instance_repair {
    enabled = true
    grace_period = "PT30M"
  }

  termination_notification {
    enabled = true
    timeout = "PT15M"
  }

  automatic_os_upgrade_policy {
    disable_automatic_rollback  = false
    enable_automatic_os_upgrade = true
  }

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 20
    pause_time_between_batches              = "PT0S"
  }

  tags = var.tags
}

# Assign users to the Application Group
resource "azurerm_role_assignment" "app_group_assignment" {
  for_each             = toset(var.assigned_users)
  scope                = azurerm_virtual_desktop_application_group.dag.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = each.value
}
