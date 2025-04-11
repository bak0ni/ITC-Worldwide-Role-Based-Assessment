resource "azurerm_virtual_wan" "vwan1" {
  resource_group_name               = azurerm_resource_group.frc-rg.name
  office365_local_breakout_category = "OptimizeAndAllow"
  name                              = "vWAN-01"
  location                          = "France Central"

  tags = {
    env = "Development"
  }
}

resource "azurerm_resource_group" "frc-rg" {
  name     = "frc-rg"
  location = "France Central"
}

resource "azurerm_resource_group" "itn-rg" {
  name     = "itn-rg"
  location = "Italy North"
}

resource "azurerm_virtual_hub" "frc-vhub" {
  virtual_wan_id      = azurerm_virtual_wan.vwan1.id
  sku                 = "Standard"
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-vhub"
  location            = "France Central"
  address_prefix      = var.vwan-region1-hub1-prefix1

  tags = {
    env = "Development"
  }
}

resource "azurerm_virtual_hub_connection" "frc-pyt-vnet-conn" {
  virtual_hub_id            = azurerm_virtual_hub.frc-vhub.id
  remote_virtual_network_id = azurerm_virtual_network.frc-pyt-vnet.id
  name                      = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_network" "frc-pyt-vnet" {
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-pyt-vnet"
  location            = "France Central"

  address_space = [
    var.frc-pyt-vnet-cidr,
  ]

  tags = {
    env      = "Development"
    archUUID = "e73c36a8-b2c5-493f-a02d-dfc0d0830f7b"
  }
}

resource "azurerm_virtual_network" "itn-pyt-vnet" {
  resource_group_name = azurerm_resource_group.itn-rg.name
  name                = "itn-pyt-vnet"
  location            = "Italy North"

  address_space = [
    var.frc-dotnet-vnet-cidr,
  ]

  tags = {
    env      = "Development"
  }
}

resource "azurerm_firewall" "frc-fw" {
  sku_tier            = "Premium"
  sku_name            = "AZFW_Hub"
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-fw"
  location            = "France Central"
  firewall_policy_id  = azurerm_firewall_policy.frc-fw-pol.id

  dns_servers = [
    "8.8.8.8",
  ]

  ip_configuration {
    public_ip_address_id = azurerm_public_ip.frc-fw-pip.id
  }

  tags = {
    env = "Development"
  }

  virtual_hub {
    virtual_hub_id  = azurerm_virtual_hub.frc-vhub.id
    public_ip_count = 1
  }
}

resource "azurerm_firewall_policy" "frc-fw-pol" {
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-fw-pol"
  location            = "France Central"
}

resource "azurerm_firewall_policy_rule_collection_group" "region1-policy1" {
  priority           = 100
  name               = "fw-pol01-rules"
  firewall_policy_id = azurerm_firewall_policy.frc-fw-pol.id

  network_rule_collection {
    priority = 100
    name     = "network_rules1"
    action   = "Allow"
    rule {
      name = "network_rule_collection1_rule1"
      destination_addresses = [
        "*",
      ]
      destination_ports = [
        "*",
      ]
      protocols = [
        "TCP",
        "UDP",
        "ICMP",
      ]
      source_addresses = [
        "*",
      ]
    }
  }
}

resource "azurerm_vpn_gateway" "region1-gateway1" {
  virtual_hub_id      = azurerm_virtual_hub.frc-vhub.id
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "vpngw-01"
  location            = "France Central"
}

resource "azurerm_point_to_site_vpn_gateway" "frcvwan-p2sgw" {
  vpn_server_configuration_id = azurerm_vpn_server_configuration.frcvwan-p2sgw-conn.id
  virtual_hub_id              = azurerm_virtual_hub.frc-vhub.id
  scale_unit                  = 1
  resource_group_name         = azurerm_resource_group.frc-rg.name
  name                        = "frcvwan-p2sgw"
  location                    = "France Central"

  connection_configuration {
    name                      = "p2s-01"
    internet_security_enabled = true
    vpn_client_address_pool {
      address_prefixes = [
        "10.1.10.0/24", "10.2.10.0/24",
        "10.3.10.0/24", "10.4.10.0/24",
        "10.5.10.0/24", "10.6.10.0/24",
        "10.7.10.0/24", "10.8.10.0/24"
      ]
    }
  }

  tags = {
    env      = "Development"
    archUUID = "e73c36a8-b2c5-493f-a02d-dfc0d0830f7b"
  }
}

resource "azurerm_vpn_server_configuration" "frcvwan-p2sgw-conn" {
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frcvwan-p2sgw-conn"
  location            = "France Central"

  azure_active_directory_authentication {
    tenant   = "GUID-goes-here"
    issuer   = "https://sts.windows.net/your-Directory-ID/"
    audience = "GUID-goes-here"
  }

  vpn_authentication_types = [
    "AAD",
  ]
}

resource "azurerm_express_route_gateway" "region1-er-gateway-01" {
  virtual_hub_id      = azurerm_virtual_hub.frc-vhub.id
  scale_units         = 1
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "er-gateway-01"
  location            = "France Central"
}

resource "azurerm_virtual_network" "frc-dotnet-vnet" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.region-1-rg-1.name
  name                = "frc-dotnet-vnet"
  location            = "France Central"
}

resource "azurerm_virtual_hub_connection" "frc-dotnet-vnet-conn" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_hub_connection" "frc-game-vnet" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_resource_group" "uks-rg" {
  name     = "region-1-rg-1"
  location = "UK South"
}

resource "azurerm_virtual_network" "itn-dotnet-vnet" {
  resource_group_name = azurerm_resource_group.itn-rg.name
  name                = "itn-dotnet-vnet"
  location            = "Italy North"

  address_space = [
    var.region-2-vnet-1-cidr,
  ]

  tags = {
    env      = "Development"
    archUUID = "e73c36a8-b2c5-493f-a02d-dfc0d0830f7b"
  }
}

resource "azurerm_virtual_network" "itn-game-vnet" {
  resource_group_name = azurerm_resource_group.region-2-rg-1.name
  name                = "itn-game-vnet"
  location            = "Italy North"

  address_space = [
    var.itn-game-vnet-cidr,
  ]

  tags = {
    env      = "Development"
  }
}

resource "azurerm_virtual_network" "itn-spec-vnet" {
  resource_group_name = azurerm_resource_group.itn-rg.name
  name                = "itn-spec-vnet"
  location            = "Italy North"

  address_space = [
    var.itn-spec-vnet-cidr,
  ]

  tags = {
    env      = "Development"
  }
}

resource "azurerm_virtual_network" "uks-pyt-vnet" {
  resource_group_name = azurerm_resource_group.uks-rg.name
  name                = "uks-pyt-vnet"
  location            = "UK South"

  address_space = [
    var.uks-pyt-vnet-cidr,
  ]

  tags = {
    env      = "Development"
  }
}

resource "azurerm_virtual_network" "uks-dotnet-vnet" {
  resource_group_name = azurerm_resource_group.uks-rg.name
  name                = "uks-dotnet-vnet"
  location            = "UK South"

  tags = {
    env      = "Development"
  }
}

resource "azurerm_virtual_network" "uks-game-vnet" {
  resource_group_name = azurerm_resource_group.uks-rg.name
  name                = "uks-game-vnet"
  location            = "UK South"

  address_space = [
    var.uks-game-vnet-cidr,
  ]

  tags = {
    env      = "Development"
  }
}

resource "azurerm_virtual_network" "uks-spec-vnet" {
  resource_group_name = azurerm_resource_group.uks-rg.name
  name                = "uks-spec-vnet"
  location            = "UK South"

  address_space = [
    var.uks-spec-vnet-cidr,
  ]

  tags = {
    env      = "Development"
  }
}

resource "azurerm_virtual_network" "frc-game-vnet" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-game-vnet"
  location            = "France Central"
}

resource "azurerm_virtual_hub_connection" "region1-connection4" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_hub_connection" "region1-connection5" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_hub_connection" "region1-connection6" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_hub_connection" "region1-connection7" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_hub_connection" "region1-connection8" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_hub_connection" "region1-connection9" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_hub_connection" "region1-connection10" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_hub_connection" "region1-connection11" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_hub_connection" "region1-connection12" {
  virtual_hub_id = azurerm_virtual_hub.frc-vhub.id
  name           = "conn-vnet1-to-vwan-hub"
}

resource "azurerm_virtual_network" "frc-spec-vnet" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-spec-vnet"
  location            = "France Central"

  ddos_protection_plan {
    enable = true
  }
}

resource "azurerm_public_ip" "frc-fw-pip" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-fw-pip"
  location            = "France Central"
}

resource "azurerm_public_ip_prefix" "public_ip_prefix" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.frc-rg.name
  location            = "France Central"
}

resource "azurerm_subnet" "frc-pyt-snet1" {
  virtual_network_name = azurerm_virtual_network.frc-pyt-vnet.name
  resource_group_name  = azurerm_resource_group.frc-rg.name
  name                 = "frc-pyt-snet1"
}

resource "azurerm_network_security_group" "frc-pytsnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-pytsnet-nsg"
  location            = "France Central"
}

resource "azurerm_network_security_group" "frc-dotsnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-dotsnet-nsg"
  location            = "France Central"
}

resource "azurerm_subnet" "itn-pyt-snet" {
  virtual_network_name = azurerm_virtual_network.itn-pyt-vnet.name
  resource_group_name  = azurerm_resource_group.itn-rg.name
  name                 = "itn-pyt-snet"
}

resource "azurerm_network_security_group" "frc-pytsnet-nsg2" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.itn-rg.name
  name                = "frc-pytsnet-nsg"
  location            = "Italy North"
}

resource "azurerm_subnet" "itn-dotnet-snet" {
  virtual_network_name = azurerm_virtual_network.itn-dotnet-vnet.name
  resource_group_name  = azurerm_resource_group.itn-rg.name
  name                 = "itn-dotnet-snet"
}

resource "azurerm_network_security_group" "itn-dotsnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.itn-rg.name
  name                = "itn-dotsnet-nsg"
  location            = "Italy North"
}

resource "azurerm_subnet" "itn-game-snet" {
  virtual_network_name = azurerm_virtual_network.itn-game-vnet.name
  resource_group_name  = azurerm_resource_group.itn-rg.name
  name                 = "itn-game-snet"
}

resource "azurerm_network_security_group" "itn-gamesnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.itn-rg.name
  name                = "itn-gamesnet-nsg"
  location            = "Italy North"
}

resource "azurerm_subnet" "itn-spec-snet" {
  virtual_network_name = azurerm_virtual_network.itn-spec-vnet2.name
  resource_group_name  = azurerm_resource_group.itn-rg.name
  name                 = "itn-spec-snet"
}

resource "azurerm_network_security_group" "itn-specsnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.itn-rg.name
  name                = "itn-specsnet-nsg"
  location            = "Italy North"
}

resource "azurerm_subnet" "uks-spec-snet" {
  virtual_network_name = azurerm_virtual_network.uks-spec-vnet3.name
  resource_group_name  = azurerm_resource_group.uks-rg.name
  name                 = "uks-spec-snet"
}

resource "azurerm_network_security_group" "uks-specsnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.uks-rg.name
  name                = "uks-specsnet-nsg"
  location            = "UK South"
}

resource "azurerm_subnet" "uks-pyt-snet" {
  virtual_network_name = azurerm_virtual_network.uks-pyt-vnet.name
  resource_group_name  = azurerm_resource_group.uks-rg.name
  name                 = "uks-pyt-snet"
}

resource "azurerm_network_security_group" "uks-pytsnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.uks-rg.name
  name                = "uks-pytsnet-nsg"
  location            = "UK South"
}

resource "azurerm_subnet" "frc-game-snet" {
  virtual_network_name = azurerm_virtual_network.uks-game-vnet2.name
  resource_group_name  = azurerm_resource_group.uks-rg.name
  name                 = "frc-game-snet"
}

resource "azurerm_network_security_group" "uks-gamesnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.uks-rg.name
  name                = "uks-gamesnet-nsg"
  location            = "UK South"
}

resource "azurerm_subnet" "frc-spec-snet" {
  virtual_network_name = azurerm_virtual_network.frc-spec-vnet3.name
  resource_group_name  = azurerm_resource_group.frc-rg.name
  name                 = "frc-spec-snet"
}

resource "azurerm_network_security_group" "frc-specsnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-specsnet-nsg"
  location            = "France Central"
}

resource "azurerm_subnet" "frc-dotnet-snet" {
  virtual_network_name = azurerm_virtual_network.frc-dotnet-vnet.name
  resource_group_name  = azurerm_resource_group.frc-rg.name
  name                 = "frc-dotnet-snet1"
}

resource "azurerm_subnet" "frc-game-snet" {
  virtual_network_name = azurerm_virtual_network.frc-pyt-vnet.name
  resource_group_name  = azurerm_resource_group.frc-rg.name
  name                 = "frc-game-snet"
}

resource "azurerm_network_security_group" "frc-gamesnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "frc-gamesnet-nsg"
  location            = "France Central"
}

resource "azurerm_route_table" "vhubRoutetable" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.frc-rg.name
  name                = "vhubRoutetable"
  location            = "France Central"
}

resource "azurerm_subnet" "uks-dotnet-snet" {
  virtual_network_name = azurerm_virtual_network.uks-dotnet-vnet.name
  resource_group_name  = azurerm_resource_group.uks-rg.name
  name                 = "uks-dotnet-snet"
}

resource "azurerm_network_security_group" "uks-dotsnet-nsg" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.uks-rg.name
  name                = "uks-dotsnet-nsg"
  location            = "UK South"
}

