variable "vnets" {
  type = map(object({
    region    = string
    vnet_cidr = string
    subnets   = map(string)
  }))
}
