variable "subscription_id" {
  description = "Azure subscription ID. Can also be supplied through ARM_SUBSCRIPTION_ID."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region. North Central US is the proposed region for Ann Arbor."
  type        = string
  default     = "northcentralus"
}

variable "resource_group_name" {
  type    = string
  default = "rg-charter-school-network"
}

variable "name_prefix" {
  type    = string
  default = "cs"
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.20.0.0/16"]
}

variable "external_subnet_prefix" {
  type    = string
  default = "10.20.1.0/24"
}

variable "internal_subnet_prefix" {
  type    = string
  default = "10.20.2.0/24"
}

variable "firewall_subnet_prefix" {
  type    = string
  default = "10.20.3.0/26"
}

variable "gateway_subnet_prefix" {
  type    = string
  default = "10.20.4.0/27"
}

variable "admin_source_cidr" {
  description = "Public administrator IP/CIDR allowed to SSH to the two external Linux VMs. Replace the documentation-only default before deployment."
  type        = string
  default     = "203.0.113.10/32"
}

variable "onprem_address_spaces" {
  description = "CIDR ranges used by the school LANs; must not overlap the Azure VNet."
  type        = list(string)
  default     = ["10.30.0.0/16"]
}

variable "onprem_vpn_public_ip" {
  description = "Public IPv4 address of the school's IPsec VPN peer/firewall."
  type        = string
  default     = ""
}

variable "vpn_shared_key" {
  description = "IPsec pre-shared key. Supply securely; do not commit it to Git."
  type        = string
  sensitive   = true
  default     = ""
}

variable "windows_admin_username" {
  type    = string
  default = "azureadmin"
}

variable "windows_admin_password" {
  description = "Windows local administrator password; use a secret store or TF_VAR_windows_admin_password."
  type        = string
  sensitive   = true
  default     = ""
}

variable "linux_admin_username" {
  type    = string
  default = "azureadmin"
}

variable "linux_ssh_public_key" {
  description = "SSH public key in OpenSSH format."
  type        = string
  default     = ""
}

variable "enable_azure_firewall" {
  description = "Deploy Azure Firewall Basic. This has a material hourly cost."
  type        = bool
  default     = true
}

variable "tags" {
  type = map(string)
  default = {
    project     = "charter-school-network"
    environment = "production"
    managed_by  = "terraform"
  }
}
