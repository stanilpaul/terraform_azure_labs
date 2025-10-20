variable "vnets" {
  description = "Here vnets contain region, vnet and subnet informations"
  ## my keys like => france, us, india => to understand my main.tf
  type = map(object({
    region    = string
    vnet_cidr = string
    subnets   = map(string)
  }))
}
variable "admin_username" {
  type = string
}
variable "admin_password" {
  type      = string
  sensitive = true
}
