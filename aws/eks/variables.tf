variable "region" {
  type    = string
  default = "us-west-2"
}

variable "name" {
  type    = string
  default = "gitops-lab"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

