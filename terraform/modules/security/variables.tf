variable "name" { type = string }
variable "vpc_id" { type = string }
variable "container_port" { type = number }
variable "allowed_ingress_cidrs" { type = list(string) }
