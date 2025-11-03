output "dns_records_linux" {
  value = { for k, v in azurerm_private_dns_a_record.ubuntu : k => v.name }
}
output "dns_records_windows" {
  value = { for k, v in azurerm_private_dns_a_record.windows : k => v.name }
}
output "private_dns_zone_name" {
  value = azurerm_private_dns_zone.internal.name
}
output "pip_windows" {
  value = try(azurerm_public_ip.windows_pip[*], "")
}
