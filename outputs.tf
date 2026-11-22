output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "vpn_gateway_public_ip" {
  value = azurerm_public_ip.vpn_gateway.ip_address
}

output "external_linux_public_ips" {
  value = { for k, p in azurerm_public_ip.external_linux : k => p.ip_address }
}

output "windows_private_ips" {
  value = { for k, nic in azurerm_network_interface.windows : k => nic.private_ip_address }
}

output "linux_private_ips" {
  value = { for k, nic in azurerm_network_interface.linux : k => nic.private_ip_address }
}

output "firewall_private_ip" {
  value = var.enable_azure_firewall ? azurerm_firewall.main[0].ip_configuration[0].private_ip_address : null
}
