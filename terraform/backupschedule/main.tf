# Terraform configuration for Azure Logic Apps to manage VMs

# Provider configuration
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource group for Logic Apps
resource "azurerm_resource_group" "logic_apps_rg" {
  name     = "vm-automation-logic-apps-rg"
  location = "East US"
}

# Storage account for VM snapshots
resource "azurerm_storage_account" "snapshot_storage" {
  name                     = "vmsnapshotstorage"
  resource_group_name      = azurerm_resource_group.logic_apps_rg.name
  location                 = azurerm_resource_group.logic_apps_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  blob_properties {
    container_delete_retention_policy {
      days = 7
    }
    delete_retention_policy {
      days = 7
    }
  }
}

# Container for VM snapshots with immutability policy
resource "azurerm_storage_container" "immutable_snapshots" {
  name                  = "vm-immutable-snapshots"
  storage_account_name  = azurerm_storage_account.snapshot_storage.name
  container_access_type = "private"
}

# Logic App for VM snapshots
resource "azurerm_logic_app_workflow" "vm_snapshot_workflow" {
  name                = "vm-snapshot-logic-app"
  location            = azurerm_resource_group.logic_apps_rg.location
  resource_group_name = azurerm_resource_group.logic_apps_rg.name
}

# Logic App for VM scheduling (deallocate and start)
resource "azurerm_logic_app_workflow" "vm_schedule_workflow" {
  name                = "vm-schedule-logic-app"
  location            = azurerm_resource_group.logic_apps_rg.location
  resource_group_name = azurerm_resource_group.logic_apps_rg.name
}

# System assigned identity for Logic Apps to access Azure Resources
resource "azurerm_user_assigned_identity" "logic_app_identity" {
  name                = "logic-app-managed-identity"
  location            = azurerm_resource_group.logic_apps_rg.location
  resource_group_name = azurerm_resource_group.logic_apps_rg.name
}

# Role assignment for VM management
resource "azurerm_role_assignment" "vm_contributor" {
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.logic_app_identity.principal_id
}

# Role assignment for storage management
resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.snapshot_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.logic_app_identity.principal_id
}

# Current subscription
data "azurerm_subscription" "current" {}

# VM Snapshot Logic App Definition
resource "azurerm_logic_app_trigger_recurrence" "daily_snapshot_trigger" {
  name         = "DailySnapshotTrigger"
  logic_app_id = azurerm_logic_app_workflow.vm_snapshot_workflow.id
  frequency    = "Day"
  interval     = 1
  time_zone    = "UTC"
  schedule {
    at_these_hours = [15]  # Run at 3 PM UTC
  }
}

# VM Schedule Logic App Definition - Deallocate Trigger
resource "azurerm_logic_app_trigger_recurrence" "deallocate_vm_trigger" {
  name         = "DeallocateVMTrigger"
  logic_app_id = azurerm_logic_app_workflow.vm_schedule_workflow.id
  frequency    = "Week"
  interval     = 1
  time_zone    = "UTC"
  schedule {
    at_these_hours   = [16]  # 4 PM UTC
    at_these_minutes = [15]  # 15 minutes
    on_these_days    = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
  }
}

# VM Schedule Logic App Definition - Start Trigger
resource "azurerm_logic_app_trigger_recurrence" "start_vm_trigger" {
  name         = "StartVMTrigger"
  logic_app_id = azurerm_logic_app_workflow.vm_schedule_workflow.id
  frequency    = "Week"
  interval     = 1
  time_zone    = "UTC"
  schedule {
    at_these_hours   = [6]  # 6 AM UTC
    at_these_minutes = [45]  # 45 minutes
    on_these_days    = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
  }
}

# ========== VM SNAPSHOT LOGIC APP WORKFLOW DEFINITION ==========
resource "azurerm_logic_app_action_http" "list_vms_action" {
  name         = "ListAllVMs"
  logic_app_id = azurerm_logic_app_workflow.vm_snapshot_workflow.id
  method       = "GET"
  uri          = "https://management.azure.com/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Compute/virtualMachines?api-version=2023-03-01"
  headers = {
    "Content-Type" = "application/json"
  }
  depends_on = [azurerm_logic_app_trigger_recurrence.daily_snapshot_trigger]
}

resource "azurerm_logic_app_action_foreach" "foreach_vm" {
  name         = "ForEachVM"
  logic_app_id = azurerm_logic_app_workflow.vm_snapshot_workflow.id
  from         = "@body('ListAllVMs').value"
  depends_on   = [azurerm_logic_app_action_http.list_vms_action]

  actions_json = <<ACTIONS
  {
    "CreateSnapshot": {
      "type": "Http",
      "inputs": {
        "method": "PUT",
        "uri": "https://management.azure.com@{items('ForEachVM').id}/beginCreateSnapshot?api-version=2023-03-01",
        "headers": {
          "Content-Type": "application/json"
        },
        "body": {
          "location": "@{items('ForEachVM').location}",
          "properties": {
            "creationData": {
              "createOption": "Copy",
              "sourceResourceId": "@{items('ForEachVM').id}"
            }
          },
          "tags": {
            "CreatedBy": "LogicApp",
            "SnapshotDate": "@{utcNow('yyyy-MM-dd')}"
          }
        }
      }
    },
    "StoreSnapshotInColdStorage": {
      "type": "ApiConnection",
      "inputs": {
        "host": {
          "connection": {
            "name": "@parameters('$connections')['azureblob']['connectionId']"
          }
        },
        "method": "post",
        "path": "/datasets/default/files",
        "queries": {
          "folderPath": "/vm-immutable-snapshots",
          "name": "@{items('ForEachVM').name}_snapshot_@{utcNow('yyyy-MM-dd')}.vhd",
          "queryParametersSingleEncoded": true
        },
        "body": "@body('CreateSnapshot')",
        "headers": {
          "x-ms-blob-type": "BlockBlob",
          "x-ms-blob-content-type": "application/octet-stream"
        }
      },
      "runAfter": {
        "CreateSnapshot": ["Succeeded"]
      }
    },
    "SetImmutabilityPolicy": {
      "type": "Http",
      "inputs": {
        "method": "PUT",
        "uri": "https://management.azure.com/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${azurerm_resource_group.logic_apps_rg.name}/providers/Microsoft.Storage/storageAccounts/${azurerm_storage_account.snapshot_storage.name}/blobServices/default/containers/${azurerm_storage_container.immutable_snapshots.name}/immutabilityPolicies/default?api-version=2021-09-01",
        "headers": {
          "Content-Type": "application/json"
        },
        "body": {
          "properties": {
            "immutabilityPeriodSinceCreationInDays": 30,
            "allowProtectedAppendWrites": false
          }
        }
      },
      "runAfter": {
        "StoreSnapshotInColdStorage": ["Succeeded"]
      }
    }
  }
  ACTIONS
}

# ========== VM SCHEDULE LOGIC APP WORKFLOW DEFINITIONS ==========

# Deallocate VMs action
resource "azurerm_logic_app_action_http" "list_vms_for_deallocate" {
  name         = "ListAllVMsForDeallocate"
  logic_app_id = azurerm_logic_app_workflow.vm_schedule_workflow.id
  method       = "GET"
  uri          = "https://management.azure.com/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Compute/virtualMachines?api-version=2023-03-01"
  headers = {
    "Content-Type" = "application/json"
  }
  depends_on = [azurerm_logic_app_trigger_recurrence.deallocate_vm_trigger]
}

resource "azurerm_logic_app_action_foreach" "foreach_vm_deallocate" {
  name         = "ForEachVMDeallocate"
  logic_app_id = azurerm_logic_app_workflow.vm_schedule_workflow.id
  from         = "@body('ListAllVMsForDeallocate').value"
  depends_on   = [azurerm_logic_app_action_http.list_vms_for_deallocate]

  actions_json = <<ACTIONS
  {
    "DeallocateVM": {
      "type": "Http",
      "inputs": {
        "method": "POST",
        "uri": "https://management.azure.com@{items('ForEachVMDeallocate').id}/deallocate?api-version=2023-03-01",
        "headers": {
          "Content-Type": "application/json"
        }
      }
    }
  }
  ACTIONS
}

# Start VMs action
resource "azurerm_logic_app_action_http" "list_vms_for_start" {
  name         = "ListAllVMsForStart"
  logic_app_id = azurerm_logic_app_workflow.vm_schedule_workflow.id
  method       = "GET"
  uri          = "https://management.azure.com/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Compute/virtualMachines?api-version=2023-03-01"
  headers = {
    "Content-Type" = "application/json"
  }
  depends_on = [azurerm_logic_app_trigger_recurrence.start_vm_trigger]
}

resource "azurerm_logic_app_action_foreach" "foreach_vm_start" {
  name         = "ForEachVMStart"
  logic_app_id = azurerm_logic_app_workflow.vm_schedule_workflow.id
  from         = "@body('ListAllVMsForStart').value"
  depends_on   = [azurerm_logic_app_action_http.list_vms_for_start]

  actions_json = <<ACTIONS
  {
    "StartVM": {
      "type": "Http",
      "inputs": {
        "method": "POST",
        "uri": "https://management.azure.com@{items('ForEachVMStart').id}/start?api-version=2023-03-01",
        "headers": {
          "Content-Type": "application/json"
        }
      }
    }
  }
  ACTIONS
}

# Outputs
output "vm_snapshot_logic_app_url" {
  value = azurerm_logic_app_workflow.vm_snapshot_workflow.access_endpoint
}

output "vm_schedule_logic_app_url" {
  value = azurerm_logic_app_workflow.vm_schedule_workflow.access_endpoint
}
