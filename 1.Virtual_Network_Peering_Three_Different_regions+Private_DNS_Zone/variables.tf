variable "vnets" {
  description = "Here vnets contain region, vnet and subnet informations"
  ## my keys like => france, us, india => to understand my main.tf
  type = map(object({
    region    = string
    vnet_cidr = string
    subnets   = map(string)
  }))
  #   default = {
  # vnets = {
  #   france = {
  #     region    = "francecentral"
  #     vnet_cidr = "10.0.0.0/16"
  #     subnets = {
  #       "public"  = "10.0.0.0/24"
  #       "private" = "10.0.1.0/24"
  #     }
  #   },
  #   india = {
  #     region    = "centralindia"
  #     vnet_cidr = "172.16.0.0/16"
  #     subnets = {
  #       "private" = "172.16.1.0/24"
  #     }
  #   },
  #   us = {
  #     region    = "eastus"
  #     vnet_cidr = "192.168.0.0/16"
  #     subnets = {
  #       "private" = "192.168.1.0/24"
  #     }
  #   }
  # }
  #   }
}
variable "admin_username" {
  type = string
  # default = "user"
}
variable "admin_password" {
  type      = string
  sensitive = true
  # default = "MyP@$$wod1sH€r€"
}
variable "domainename" {
  type = string
}
