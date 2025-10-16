resource "azurerm_resource_group" "this" {
  for_each = var.vnets
  name     = "rg-${each.key}"
  location = each.value.region
}

resource "azurerm_network_security_group" "nsg" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        location    = value.region
        rg_name     = azurerm_resource_group.this[key].name
        subnet_name = x
        is_public   = x == "public"
      }
    }
  ]...)

  name                = "nsg-${each.value.subnet_name}-${each.key}"
  location            = each.value.location
  resource_group_name = each.value.rg_name

  dynamic "security_rule" {
    for_each = each.value.is_public ? ["rdp_rule"] : []

    content {
      name                       = "AllowRDPFromMyIP"
      priority                   = 1001
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}
resource "azurerm_virtual_network" "this" {
  for_each            = var.vnets
  name                = "vnet-${each.key}"
  location            = azurerm_resource_group.this[each.key].location
  resource_group_name = azurerm_resource_group.this[each.key].name
  address_space       = [each.value.vnet_cidr]
}

resource "azurerm_subnet" "this" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        vnet_key    = key
        subnet_name = x
        cidr        = y
      }
    }
  ]...)
  name                 = each.value.subnet_name
  resource_group_name  = azurerm_resource_group.this[each.value.vnet_key].name
  virtual_network_name = azurerm_virtual_network.this[each.value.vnet_key].name
  address_prefixes     = [each.value.cidr]

}
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        subnet_id = azurerm_subnet.this["${key}-${x}"].id
        nsg_id    = azurerm_network_security_group.nsg["${key}-${x}"].id
      }
    }
  ]...)
  subnet_id                 = each.value.subnet_id
  network_security_group_id = each.value.nsg_id
}
