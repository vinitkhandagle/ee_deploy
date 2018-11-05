variable "aws_region" {}
variable "aws_profile" {}
data "aws_availability_zones" "available" {}

# Create a VPC
variable "vpc_cidr" {
  description = "CIDR for the whole VPC"
}

variable "cidrs" {
  type = "map"
}

variable "public_subnet_cidr" {
  description = "CIDR for the Public Subnet"
  default     = "172.20.0.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the Private Subnet"
  default     = "172.20.1.0/24"
}

## Instance Variables
variable "control_instance_type" {}

variable "control_ami" {}

variable "private_instance_type" {}
variable "private_ami" {}
