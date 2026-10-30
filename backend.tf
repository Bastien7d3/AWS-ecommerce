# Backend S3 partagé pour le travail collaboratif
# Pour une évaluation autonome sur un compte AWS séparé, ce fichier est désactivé (renommé en .disabled)
terraform {
  backend "s3" {
    bucket         = "cloudshop-tfstate-fisa2026-unique"
    key            = "global/s3/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "cloudshop-tfstate-locks"
    encrypt        = true
  }
}
