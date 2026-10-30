variable "project_name" {
  description = "Préfixe commun des ressources"
  type        = string
}

variable "account_id" {
  description = "Identifiant du compte AWS pour unicité mondiale"
  type        = string
  default     = ""
}
