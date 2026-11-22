data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.name_prefix}-vnet"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "external" {
  name                 = "snet-external"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.external_subnet_prefix]
}

resource "azurerm_subnet" "internal" {
  name                 = "snet-internal"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.internal_subnet_prefix]
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.firewall_subnet_prefix]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.gateway_subnet_prefix]
}

# NSGs: external Linux servers expose HTTP/S publicly; SSH is restricted to admin_source_cidr.
resource "azurerm_network_security_group" "external" {
  name                = "${var.name_prefix}-nsg-external"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  security_rule {
    name                       = "Allow-SSH-From-Admin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_source_cidr
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-HTTP-HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  tags = var.tags
}

resource "azurerm_network_security_group" "internal" {
  name                = "${var.name_prefix}-nsg-internal"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  # Default Azure VNet inbound rules allow VNet-to-VNet traffic. No public IPs
  # are assigned to internal VMs. RDP/SSH should be reached over the VPN.
  security_rule {
    name                       = "Allow-RDP-from-OnPrem"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefixes    = var.onprem_address_spaces
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-SSH-from-OnPrem"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.onprem_address_spaces
    destination_address_prefix = "*"
  }
  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "external" {
  subnet_id                 = azurerm_subnet.external.id
  network_security_group_id = azurerm_network_security_group.external.id
}

resource "azurerm_subnet_network_security_group_association" "internal" {
  subnet_id                 = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.internal.id
}

# Public IPs for the external Linux hosts.
resource "azurerm_public_ip" "external_linux" {
  count               = 2
  name                = "${var.name_prefix}-pip-ext-linux-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Azure Firewall public endpoint and policy. Firewall Basic is a lower-cost
# managed firewall tier; confirm regional/SKU availability and throughput needs.
resource "azurerm_public_ip" "firewall" {
  count               = var.enable_azure_firewall ? 1 : 0
  name                = "${var.name_prefix}-pip-firewall"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_firewall" "main" {
  count               = var.enable_azure_firewall ? 1 : 0
  name                = "${var.name_prefix}-azure-firewall"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id  = azurerm_firewall_policy.main[0].id
  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }
  tags = var.tags
}

resource "azurerm_firewall_policy" "main" {
  count               = var.enable_azure_firewall ? 1 : 0
  name                = "${var.name_prefix}-firewall-policy"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  tags                = var.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "baseline" {
  count              = var.enable_azure_firewall ? 1 : 0
  name               = "baseline-egress"
  firewall_policy_id = azurerm_firewall_policy.main[0].id
  priority           = 100

  network_rule_collection {
    name     = "allow-basic-outbound"
    priority = 100
    action   = "Allow"
    rule {
      name                  = "allow-dns-to-azure-resolver"
      protocols             = ["UDP", "TCP"]
      source_addresses      = [var.internal_subnet_prefix]
      destination_addresses = ["168.63.129.16"]
      destination_ports     = ["53"]
    }
    rule {
      name                  = "allow-web-egress"
      protocols             = ["TCP"]
      source_addresses      = [var.internal_subnet_prefix]
      destination_addresses = ["*"]
      destination_ports     = ["80", "443"]
    }
    rule {
      name                  = "allow-school-to-internal-services"
      protocols             = ["TCP", "UDP"]
      source_addresses      = var.onprem_address_spaces
      destination_addresses = [var.internal_subnet_prefix]
      destination_ports     = ["53", "88", "123", "135", "137-139", "389", "445", "464", "636", "1812", "1813", "3268", "3269", "3389", "49152-65535", "9389"]
    }
    rule {
      name                  = "allow-internal-to-school"
      protocols             = ["TCP", "UDP"]
      source_addresses      = [var.internal_subnet_prefix]
      destination_addresses = var.onprem_address_spaces
      destination_ports     = ["53", "123", "1812", "1813"]
    }
  }
}

# Force internal-subnet default internet traffic through Azure Firewall.
resource "azurerm_route_table" "internal" {
  count                         = var.enable_azure_firewall ? 1 : 0
  name                          = "${var.name_prefix}-rt-internal"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  disable_bgp_route_propagation = true
  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.main[0].ip_configuration[0].private_ip_address
  }
  dynamic "route" {
    for_each = var.onprem_address_spaces
    content {
      name                   = "school-${replace(replace(route.value, "/", "-"), ".", "-")}"
      address_prefix         = route.value
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = azurerm_firewall.main[0].ip_configuration[0].private_ip_address
    }
  }
  tags = var.tags
}

# Send VPN-arriving traffic for the internal workload subnet through the firewall.
# Gateway route propagation remains enabled so the gateway retains learned routes.
resource "azurerm_route_table" "gateway" {
  count               = var.enable_azure_firewall ? 1 : 0
  name                = "${var.name_prefix}-rt-gateway"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  route {
    name                   = "internal-subnet-via-firewall"
    address_prefix         = var.internal_subnet_prefix
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.main[0].ip_configuration[0].private_ip_address
  }
  tags = var.tags
}

resource "azurerm_subnet_route_table_association" "gateway" {
  count          = var.enable_azure_firewall ? 1 : 0
  subnet_id      = azurerm_subnet.gateway.id
  route_table_id = azurerm_route_table.gateway[0].id
}

resource "azurerm_subnet_route_table_association" "internal" {
  count          = var.enable_azure_firewall ? 1 : 0
  subnet_id      = azurerm_subnet.internal.id
  route_table_id = azurerm_route_table.internal[0].id
}

# Site-to-site VPN: the school's on-premises VPN device peers with Azure VPN Gateway.
resource "azurerm_public_ip" "vpn_gateway" {
  name                = "${var.name_prefix}-pip-vpn-gateway"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "main" {
  name                = "${var.name_prefix}-vpngw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1"
  active_active       = false
  enable_bgp          = false
  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
  tags = var.tags
}

resource "azurerm_local_network_gateway" "school" {
  name                = "${var.name_prefix}-school-lng"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  gateway_address     = var.onprem_vpn_public_ip
  address_space       = var.onprem_address_spaces
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway_connection" "school" {
  name                       = "${var.name_prefix}-school-s2s"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.main.id
  local_network_gateway_id   = azurerm_local_network_gateway.school.id
  shared_key                 = var.vpn_shared_key
  enable_bgp                 = false
  tags                       = var.tags
}

locals {
  windows_servers = {
    dc01 = { name = "DC01", ip = "10.20.2.10" }
    dc02 = { name = "DC02", ip = "10.20.2.11" }
    msca = { name = "MSCA01", ip = "10.20.2.12" }
    nps  = { name = "NPS01", ip = "10.20.2.13" }
  }
  linux_servers = {
    ext01 = { name = "EXT-LINUX01", ip = "10.20.1.10", subnet = "external" }
    ext02 = { name = "EXT-LINUX02", ip = "10.20.1.11", subnet = "external" }
    int01 = { name = "INT-LINUX01", ip = "10.20.2.20", subnet = "internal" }
    int02 = { name = "INT-LINUX02", ip = "10.20.2.21", subnet = "internal" }
  }
}

resource "azurerm_network_interface" "windows" {
  for_each            = local.windows_servers
  name                = "${var.name_prefix}-nic-${each.key}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
  tags = var.tags
}

resource "azurerm_windows_virtual_machine" "servers" {
  for_each            = local.windows_servers
  name                = each.value.name
  computer_name       = each.value.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_F4s_v2"
  admin_username      = var.windows_admin_username
  admin_password      = var.windows_admin_password
  network_interface_ids = [azurerm_network_interface.windows[each.key].id]
  provision_vm_agent  = true
  enable_automatic_updates = true
  patch_mode          = "AutomaticByOS"
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
  boot_diagnostics {}
  tags = var.tags
}

resource "azurerm_network_interface" "linux" {
  for_each            = local.linux_servers
  name                = "${var.name_prefix}-nic-${each.key}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = each.value.subnet == "external" ? azurerm_subnet.external.id : azurerm_subnet.internal.id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
    public_ip_address_id          = each.value.subnet == "external" ? azurerm_public_ip.external_linux[each.key == "ext01" ? 0 : 1].id : null
  }
  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "servers" {
  for_each            = local.linux_servers
  name                = each.value.name
  computer_name       = each.value.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_F2s_v2"
  admin_username      = var.linux_admin_username
  network_interface_ids = [azurerm_network_interface.linux[each.key].id]
  disable_password_authentication = true
  admin_ssh_key {
    username   = var.linux_admin_username
    public_key = var.linux_ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  boot_diagnostics {}
  tags = var.tags
}
