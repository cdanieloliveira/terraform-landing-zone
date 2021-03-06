provider "azurerm" {
  # The "feature" block is required for AzureRM provider 2.x.
  # If you are using version 1.x, the "features" block is not allowed.
  version = "~>2.2.0"
  features {}
}

provider "random" {
  version = ">= 2.2.0"
}

# Resource Group #
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}rg-landingzone"
  location = var.location
  tags     = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Networking Stuff

## Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}vnet-hub"
  address_space       = ["172.16.0.0/16"]
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = var.tags
  dns_servers         = ["172.16.0.4", "172.16.0.5"]

}

resource "azurerm_virtual_network" "spoke1" {
  name                = "${var.prefix}vnet-spoke1"
  address_space       = ["172.17.0.0/16"]
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = var.tags
}
resource "azurerm_virtual_network" "spoke2" {
  name                = "${var.prefix}vnet-spoke2"
  address_space       = ["172.18.0.0/16"]
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = var.tags
}

## Subnets
resource "azurerm_subnet" "identity" {
  name                 = "Identity"
  address_prefix       = "172.16.0.0/24"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "vpn" {
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  name                 = "GatewaySubnet"
  address_prefix       = "172.16.3.192/28"
}

resource "azurerm_subnet" "management" {
  name                 = "management"
  address_prefix       = "172.16.1.0/24"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "app" {
  name                 = "frontend"
  address_prefix       = "172.17.0.0/24"
  virtual_network_name = azurerm_virtual_network.spoke1.name
  resource_group_name  = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "sql" {
  name                 = "backend"
  address_prefix       = "172.17.1.0/24"
  virtual_network_name = azurerm_virtual_network.spoke1.name
  resource_group_name  = azurerm_resource_group.rg.name
}

# Vnet Peerings
resource "azurerm_virtual_network_peering" "hub-spoke1" {
  name                      = "hub-spoke1"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.vnet.name
  remote_virtual_network_id = azurerm_virtual_network.spoke1.id
}

resource "azurerm_virtual_network_peering" "spoke1-hub" {
  name                      = "spoke1-hub"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.spoke1.name
  remote_virtual_network_id = azurerm_virtual_network.vnet.id
  allow_forwarded_traffic   = false
}

resource "azurerm_virtual_network_peering" "hub-spoke2" {
  name                      = "hub-spoke2"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.vnet.name
  remote_virtual_network_id = azurerm_virtual_network.spoke2.id
}

resource "azurerm_virtual_network_peering" "spoke2-hub" {
  name                      = "spoke2-hub"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.spoke2.name
  remote_virtual_network_id = azurerm_virtual_network.vnet.id
  allow_forwarded_traffic   = false
}

# VPN Gateway
resource "azurerm_public_ip" "vpn" {
  name                = "${var.prefix}gw-prd-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

data "azurerm_public_ip" "vpn" {
  name                = azurerm_public_ip.vpn.name
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_virtual_network_gateway" "vpn" {
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  name                = "${var.prefix}gw"
  type                = "vpn"
  sku                 = "VpnGw1"
  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.vpn.id
  }
  tags = var.tags
}

resource "random_string" "vpn" {
  length           = 16
  special          = true
  override_special = "@#$%&*"
}

resource "azurerm_virtual_network_gateway_connection" "vpn" {
  shared_key                 = random_string.vpn.result
  location                   = azurerm_resource_group.rg.location
  tags                       = var.tags
  name                       = "${var.prefix}onpremises-site01"
  type                       = "IPSec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn.id
  local_network_gateway_id   = azurerm_local_network_gateway.vpn.id
  resource_group_name        = azurerm_resource_group.rg.name
}

resource "azurerm_local_network_gateway" "vpn" {
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  name                = "${var.prefix}localgw-onprem01"
  gateway_address     = var.localgwIP
  address_space       = var.localgwAddress
  tags                = var.tags
}

## NSGs and rules ##
resource "azurerm_network_security_group" "identity" {
  name                = "${var.prefix}nsg-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_network_security_group" "management" {
  name                = "${var.prefix}nsg-management"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_network_security_group" "app" {
  name                = "${var.prefix}nsg-app"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_network_security_group" "sql" {
  name                = "${var.prefix}nsg-SQL"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "RDP" {
  name                        = "Allow_RDP_in"
  direction                   = "inbound"
  priority                    = 100
  protocol                    = "*"
  access                      = "allow"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = "192.168.0.100"
  destination_address_prefix  = "*"
  network_security_group_name = azurerm_network_security_group.management.name
  resource_group_name         = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "HTTTP-HTTPS" {
  name                        = "Allow_HTTP-HTTPS_in"
  direction                   = "inbound"
  priority                    = 100
  protocol                    = "*"
  access                      = "allow"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443"]
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  network_security_group_name = azurerm_network_security_group.app.name
  resource_group_name         = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "sql" {
  name                        = "Allow_SQL_in"
  direction                   = "inbound"
  priority                    = 100
  protocol                    = "*"
  access                      = "allow"
  source_port_range           = "*"
  destination_port_range      = "3306"
  source_address_prefix       = azurerm_subnet.app.address_prefix
  destination_address_prefix  = "*"
  network_security_group_name = azurerm_network_security_group.sql.name
  resource_group_name         = azurerm_resource_group.rg.name
}

## NSG Association
resource "azurerm_subnet_network_security_group_association" "identity" {
  network_security_group_id = azurerm_network_security_group.identity.id
  subnet_id                 = azurerm_subnet.identity.id
}

resource "azurerm_subnet_network_security_group_association" "management" {
  network_security_group_id = azurerm_network_security_group.management.id
  subnet_id                 = azurerm_subnet.management.id
}

resource "azurerm_subnet_network_security_group_association" "app" {
  network_security_group_id = azurerm_network_security_group.app.id
  subnet_id                 = azurerm_subnet.app.id
}

resource "azurerm_subnet_network_security_group_association" "sql" {
  network_security_group_id = azurerm_network_security_group.sql.id
  subnet_id                 = azurerm_subnet.sql.id
}

# Compute Resources

## Availability Set

resource "azurerm_availability_set" "adds" {
  name                         = "${var.prefix}adds-avset"
  location                     = azurerm_resource_group.rg.location
  resource_group_name          = azurerm_resource_group.rg.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true
}

resource "azurerm_network_interface" "adds" {

  name                = "${var.prefix}${var.adds_name}-nic${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  count               = var.adds_instance_count

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.identity.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "adds" {
  name                  = "${var.prefix}${var.adds_name}${count.index}"
  computer_name         = "${var.prefix}${var.adds_name}${count.index}"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  availability_set_id   = azurerm_availability_set.adds.id
  size                  = "Standard_B2ms"
  admin_username        = "adminuser"
  admin_password        = "P@$$w0rd1234!"
  network_interface_ids = [element(azurerm_network_interface.adds.*.id, count.index)]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "${var.prefix}${var.adds_name}${count.index}_os_disk"
  }
  count = var.adds_instance_count
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
  tags = var.tags
}