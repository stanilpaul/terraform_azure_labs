###################################################################################################
###################################################################################################
#                 Welcome to this Lab practice

# For some good practice, I hide TFVARS file, PROVIDER file form VSC
# But I also add default value in Variables.tf file and in main.tf in comment section
# Please, you have to uncomment some section or create them

###################################################################################################
###################################################################################################


#####
# Provider section to uncomment or create new file for this
#####

# terraform {
#   required_providers {
#     azurerm = {
#       source  = "hashicorp/azurerm"
#       version = "~> 4.48.0"
#     }
#   }
#   required_version = ">= 1.1.0"
# }
# provider "azurerm" {
#   features {

#   }
#   subscription_id = "Your subcription id"
# }

#####
##RG creation
#####
resource "azurerm_resource_group" "this" {
  for_each = var.vnets
  name     = "rg-${each.key}"
  location = each.value.region
}
resource "azurerm_virtual_network" "this" {
  for_each            = var.vnets
  name                = "vnet-${each.key}"
  location            = azurerm_resource_group.this[each.key].location
  resource_group_name = azurerm_resource_group.this[each.key].name
  address_space       = [each.value.vnet_cidr]
  ## I have only one vnet for each RG but even if you put more vnets, it will work! => best method used => for_each
}

resource "azurerm_subnet" "this" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        vnet_key    = key # ex: france, us, india
        subnet_name = x   # ex: private/public
        cidr        = y   # "10.0.0.0/24"
      }
    }
  ]...)
  name                 = each.value.subnet_name
  resource_group_name  = azurerm_resource_group.this[each.value.vnet_key].name
  virtual_network_name = azurerm_virtual_network.this[each.value.vnet_key].name
  address_prefixes     = [each.value.cidr]

}

#####
#NSG
# As in terraform I cannot put directly two for , I use MERGE 
# first for, to fetch first level of map ==>( france, us, india)
# secound for, to fetch second level of map which is inside first fetch "SUBNETS"
# ! Use same key accross different resource block ==> easy to reference
#####
resource "azurerm_network_security_group" "nsg" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        location    = value.region
        rg_name     = azurerm_resource_group.this[key].name
        subnet_name = x             # private/public
        is_public   = x == "public" # I check if the subnet name is public ==> my infra hava only two type of subnet name "private" / "public"
      }
    }
  ]...)

  name                = "nsg-${each.value.subnet_name}-${each.key}"
  location            = each.value.location
  resource_group_name = each.value.rg_name
  ## for private subnet we don't need to set rule beacause, vnet to vnet all ports are default open
  ## for public I only open 3389 ==> ofcause, this is for educational purpose / otherwise use bastion or other methods
  dynamic "security_rule" {
    for_each = each.value.is_public ? ["rdp_rule"] : []

    content {
      name                       = "AllowRDPFromMyIP"
      priority                   = 1001
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["3389", "80"] ## only for testing
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}
#####
## here we associate subnet with nsg
#####
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

###############
//Here lets do the peering
#################
resource "azurerm_virtual_network_peering" "this" {
  ## serproduct will give all the combination possible with two map ==> "france","france"; "france","us"; "france","india"
  ## it is terraform build in function
  for_each = {
    for pair in setproduct(keys(var.vnets), keys(var.vnets)) :
    "${pair[0]}-to-${pair[1]}" => {
      source_key     = pair[0]
      dest_key       = pair[1]
      source_vnet_id = azurerm_virtual_network.this[pair[0]].id
      dest_vnet_id   = azurerm_virtual_network.this[pair[1]].id
    }
    if pair[0] != pair[1] # This is to avoid two same network peering like => france_vnet peering to france_vnet
  }
  name                      = each.key
  resource_group_name       = azurerm_resource_group.this[each.value.source_key].name
  virtual_network_name      = azurerm_virtual_network.this[each.value.source_key].name
  remote_virtual_network_id = each.value.dest_vnet_id

  ## optional depend on your need
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

#####
## Lets create app servers with apache2 in every private subnet
#####
resource "azurerm_network_interface" "ubuntu_nic" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        vnet_key  = key
        subnet_id = azurerm_subnet.this["${key}-${x}"].id
      }
      if x == "private" # we create only this ubuntu machine in private subnets
    }
  ]...)

  name                = "nic-ubuntu-${each.value.vnet_key}"
  location            = azurerm_resource_group.this[each.value.vnet_key].location
  resource_group_name = azurerm_resource_group.this[each.value.vnet_key].name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}
# here is our machine 
resource "azurerm_linux_virtual_machine" "ubuntu" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        vnet_key    = key
        subnet_name = x
        cidr        = y
      }
      if x == "private" # we create only this ubuntu machine in private subnets
    }
  ]...)

  name                            = "apache2-${each.value.vnet_key}"
  resource_group_name             = azurerm_resource_group.this[each.value.vnet_key].name
  location                        = azurerm_resource_group.this[each.value.vnet_key].location
  size                            = "Standard_B1s" # ~2 Go RAM
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.ubuntu_nic[each.key].id
  ]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }


  custom_data = base64encode(templatefile("${path.module}/web-server-cloud-init.txt", {
    vm_name = "apache2-${each.value.vnet_key}"
    region  = each.value.vnet_key
    subnet  = each.value.subnet_name
  }))
}

#####
# Lets create a windows server , with IIS install + its a spot instance (Cost effective)
#####

#nic_windows
resource "azurerm_network_interface" "windows_nic" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        vnet_key  = key
        subnet_id = azurerm_subnet.this["${key}-${x}"].id
      }
      if x == "public" # this will make sure I create only windows in public subnet
    }
  ]...)
  name                = "nic-win${each.value.vnet_key}"
  location            = azurerm_resource_group.this[each.value.vnet_key].location
  resource_group_name = azurerm_resource_group.this[each.value.vnet_key].name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.windows_pip[each.key].id
  }

}


## Public ip for my windows machine
resource "azurerm_public_ip" "windows_pip" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        location = azurerm_resource_group.this[key].location
        rg       = azurerm_resource_group.this[key].name
      }
      if x == "public" # this will make sure I create only windows in public subnet
    }
  ]...)

  name                = "pip-win-${each.key}"
  location            = each.value.location
  resource_group_name = each.value.rg
  allocation_method   = "Static"
  sku                 = "Basic"
}

## my windows vm
resource "azurerm_windows_virtual_machine" "windows" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        vnet_key    = key
        subnet_name = x
        cidr        = y
      }
      if x == "public" # this will make sure I create only windows in public subnet
    }
  ]...)

  name                = "windows-${each.value.vnet_key}"
  resource_group_name = azurerm_resource_group.this[each.value.vnet_key].name
  location            = azurerm_resource_group.this[each.value.vnet_key].location
  size                = "Standard_D2s_v4"
  admin_username      = var.admin_username
  admin_password      = var.admin_password


  network_interface_ids = [
    azurerm_network_interface.windows_nic[each.key].id
  ]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  ####### SPOT ####
  priority        = "Spot"
  eviction_policy = "Deallocate"

}
resource "azurerm_virtual_machine_extension" "windows_iis" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        vm_id = azurerm_windows_virtual_machine.windows["${key}-${x}"].id
      }
      if x == "public"
    }
  ]...)

  name                       = "install-iis"
  virtual_machine_id         = each.value.vm_id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"Start-Transcript C:\\iis-install.log; Install-WindowsFeature -Name Web-Server -IncludeManagementTools; Set-Content -Path 'C:\\inetpub\\wwwroot\\index.html' -Value '<html><body><h1>Hello, Welcome to ${each.key}!</h1></body></html>'; Stop-Transcript\""
  })

  #permet à Terraform de recréer l'extension proprement si besoin
  lifecycle {
    create_before_destroy = true
  }

  # Dépend de la VM pour éviter les race conditions
  depends_on = [azurerm_windows_virtual_machine.windows]
}

########################
#Private DNS Zone
########################
resource "azurerm_private_dns_zone" "internal" {
  name                = var.domainename
  resource_group_name = azurerm_resource_group.this["france"].name # I create my private dns zone in France RG
}
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = var.vnets
  name                  = "link-to-vnet-${each.key}"
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  resource_group_name   = azurerm_resource_group.this["france"].name
  virtual_network_id    = azurerm_virtual_network.this[each.key].id

  registration_enabled = false
  depends_on           = [azurerm_private_dns_zone.internal]
}
# DNS records - Linux 
resource "azurerm_private_dns_a_record" "ubuntu" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        rg      = key
        vm_name = "apache2-${key}"
        nic_id  = azurerm_network_interface.ubuntu_nic["${key}-${x}"].id
      }
      if x == "private"
    }
  ]...)

  name                = each.value.vm_name
  zone_name           = azurerm_private_dns_zone.internal.name
  resource_group_name = azurerm_resource_group.this["france"].name

  ttl = 300
  records = [
    # each.key example: "france-private" → used to index both NIC and VM resources
    try(azurerm_linux_virtual_machine.ubuntu[each.key].private_ip_address, "")
  ]

  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
}

# DNS records - Windows
resource "azurerm_private_dns_a_record" "windows" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        rg      = key
        vm_name = "windows-${key}"
        nic_id  = azurerm_network_interface.windows_nic["${key}-${x}"].id
      }
      if x == "public"
    }
  ]...)

  name                = each.value.vm_name
  zone_name           = azurerm_private_dns_zone.internal.name
  resource_group_name = azurerm_resource_group.this["france"].name

  ttl = 300
  records = [
    # each.key example: "france-private" → used to index both NIC and VM resources
    try(azurerm_windows_virtual_machine.windows[each.key].private_ip_address, "")
  ]

  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
}
