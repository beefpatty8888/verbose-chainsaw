# https://developer.hashicorp.com/terraform/tutorials/configuration-language/sensitive-variables
variable "db_username" {
  description = "wordpress rds username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "wordpress rds password"
  type        = string
  sensitive   = true
}
