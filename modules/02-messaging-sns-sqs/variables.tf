variable "project_name" {
  description = "Nom du projet pour préfixer les files SQS et topics SNS"
  type        = string
}

variable "notification_email" {
  description = "Adresse e-mail optionnelle pour recevoir les notifications SNS (laisser vide si non souhaité)"
  type        = string
  default     = ""
}
