variable "aws_region" {
  description = "Région AWS cible"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Préfixe des ressources"
  type        = string
  default     = "cloudshop-test"
}
