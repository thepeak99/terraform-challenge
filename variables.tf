variable "vm_count" {
  description = "Number of VM instances to create"
  type        = number
  default     = 2
}

variable "vm_flavor" {
  description = "Instance type for VMs"
  type        = string
  default     = "t3.micro"
}

output "admin_passwords" {
  value     = random_password.admin_passwords.*.result
  sensitive = true
}

output "pings"  {
  value = data.external.pings.*.result.body
}
