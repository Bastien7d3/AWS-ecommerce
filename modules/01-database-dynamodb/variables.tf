variable "project_name" {
  description = "Nom du projet pour préfixer les tables et le bucket S3"
  type        = string
}

variable "account_id" {
  description = "Identifiant du compte AWS (pour garantir un nom de bucket S3 unique)"
  type        = string
}
