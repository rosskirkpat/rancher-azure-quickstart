variable "shared_gallery_subscription_id" {
  type        = string
  description = "The subscription ID of the Shared Image Gallery."
}

variable "shared_gallery_resource_group_name" {
  type        = string
  description = "The Shared Image Gallery resource group name."
}

variable "shared_gallery_name" {
  type        = string
  description = "The Shared Image Gallery name."
}

variable "shared_gallery_image_name" {
  type        = string
  description = "The Shared Image Gallery image name."
  default     = "RKE2Base2022"
}

variable "shared_gallery_image_version" {
  type        = string
  description = "The Shared Image Gallery image version."
  default     = "1.0.0"
}

variable "vm_size" {
  type        = string
  description = "The packer VM size."
  default     = "Standard_D4as_v5"
}

variable "location" {
  type        = string
  description = "The Azure Region"
  default     = "East US"
}

variable "managed_resource_group" {
  type        = string
  description = "The resource group for the Packer managed image."
}

variable "managed_image_name" {
  type        = string
  description = "The Packer managed image name."
  default     = "RKE2Base2022"
}

variable "tags" {
  type = map(string)
  default = {
    RancherTeam = "team4"
    Environment = "dev"
  }
}