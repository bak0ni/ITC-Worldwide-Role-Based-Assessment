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

variable "frc-game-vnet-cidr" {
  type    = string
  default = "10.3.0.0/16"
}

variable "frc-soec-vnet-cidr" {
  type    = string
  default = "10.4.0.0/16"
}

variable "itn-pyt-vnet-cidr" {
  type    = string
  default = "10.5.0.0/16"
}

variable "itn-dotnet-vnet-cidr" {
  type    = string
  default = "10.6.0.0/16"
}

variable "itn-game-vnet-cidr" {
  type    = string
  default = "10.7.0.0/16"
}

variable "itn-spec-vnet-cidr" {
  type    = string
  default = "10.8.0.0/16"
}

variable "uks-pyt-vnet-cidr" {
  type    = string
  default = "10.9.0.0/16"
}

variable "uks-dotnet-vnet-cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "uks-game-vnet-cidr" {
  type    = string
  default = "10.11.0.0/16"
}

variable "uks-spec-vnet-cidr" {
  type    = string
  default = "10.12.0.0/16"
}

variable "tags" {
  description = "Default tags to apply to all resources."
  type        = map(any)
  default = {
    env      = "Development"
    proj     = "Zero Trust"
  }
}

variable "vwan-region1-hub1-prefix1" {
  type    = string
  default = "10.0.0.0/16"
}

