## I hide form VCS some files due to sensitive data and production best practice :
## - terraform.rfvars => all data
## providers.tf => which have my subscription id
## Please, if you use this project, please create those file to avoid error/ include in main

##RG creation
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

## NSG creating
## As in terraform I cannot put directly two for , I use MERGE 
## first for, to fetch first level of map ==>( france, us, india)
## secound for, to fetch second level of map which is inside first fetch "SUBNETS"
## ! Use same key accross different resource block ==> easy to reference
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
  ## for public I only open 3389 ==> of cause, this is for educational purpose / otherwise use bastion or other methods
  dynamic "security_rule" {
    for_each = each.value.is_public ? ["rdp_rule"] : []

    content {
      name                       = "AllowRDPFromMyIP"
      priority                   = 1001
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389" ## only for testing
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}

## here we associate subnet with nsg
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
  ## serproduct will give all the combination possible with two map
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

##
## Lets create app servers with apache2 in every private subnet
## starting with nic 
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

  name                = "apache2-${each.value.vnet_key}"
  resource_group_name = azurerm_resource_group.this[each.value.vnet_key].name
  location            = azurerm_resource_group.this[each.value.vnet_key].location
  size                = "Standard_B1s" # ~2 Go RAM
  admin_username      = var.admin_username
  admin_password      = var.admin_password

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
}
# here custom script to install apache2
resource "azurerm_virtual_machine_extension" "ubuntu_apache" {
  for_each = merge([
    for key, value in var.vnets : {
      for x, y in value.subnets :
      "${key}-${x}" => {
        vm_id = azurerm_linux_virtual_machine.ubuntu["${key}-${x}"].id
      }
      if x == "private"
    }
  ]...)

  name                       = "install-apache"
  virtual_machine_id         = each.value.vm_id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true

  settings = jsondecode({
    commandToExecute = "sudo apt update && sudo apt install -y apache2 && echo '<h1>Hello from ${each.key}!</h1>' | tee /var/www/hjtml/index.html"
  })
}


##
## Lets create a windows server , with IIS install + its a spot instance (Cost effective)
##

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


## Il me reste creation of public ip
## custom data

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
  size                = "Standard_D4s_v4" # 4 vcpu, 16go ram
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
