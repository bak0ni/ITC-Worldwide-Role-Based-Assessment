variable "random_string" {
  description = "Description"
  type        = string
  default     = "two"
}

variable "frc-pyt-vnet-cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "frc-dotnet-vnet-cidr" {
  type    = string
  default = "10.2.0.0/16"
}

variable "tags" {
  description = "Default tags to apply to all resources."
  type        = map(any)
  default = {
    env      = "Development"
  }
}

variable "vwan-region1-hub1-prefix1" {
  type    = string
  default = "10.0.0.0/16"
}

