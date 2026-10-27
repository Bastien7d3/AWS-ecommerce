variable "aws_region" {
  description = "Région AWS cible"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Préfixe commun des ressources du projet"
  type        = string
  default     = "cloudshop"
}

variable "notification_email" {
  description = "Adresse e-mail optionnelle pour recevoir les confirmations SNS (laisser vide si non souhaité)"
  type        = string
  default     = ""
}

variable "enable_autoscaling_alb" {
  description = "Passe à true pour déployer le Load Balancer Multi-AZ et l'Auto Scaling Group (1 à 4 EC2) au lieu d'une EC2 unique"
  type        = bool
  default     = false
}
