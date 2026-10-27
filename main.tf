# ==============================================================================
# ORCHESTRATION GLOBALE DU PROJET CLOUDSHOP AWS (FISA 2026)
# Fichier racine unique reliant les 5 modules dans ./modules/ :
#   01-database-dynamodb <-> 02-messaging-sns-sqs <-> 03-serverless-lambda
#   <-> 04-frontend-ec2 <-> 05-batch-ec2-spot
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  # à suppr à la fin
  backend "s3" {
    bucket         = "cloudshop-tfstate-fisa2026-unique"
    key            = "global/s3/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "cloudshop-tfstate-locks"
    encrypt        = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "CloudShop-FISA2026"
      ManagedBy = "Terraform"
    }
  }
}

# ------------------------------------------------------------------------------
# VARIABLES GLOBALES
# ------------------------------------------------------------------------------
variable "aws_region" {
  description = "Région AWS cible (Paris)"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Préfixe commun des ressources du projet"
  type        = string
  default     = "cloudshop"
}

variable "notification_email" {
  description = "Adresse e-mail optionnelle pour recevoir toutes les notifications SNS"
  type        = string
  default     = ""
}

variable "enable_autoscaling_alb" {
  description = "Passe à true pour déployer le Load Balancer Multi-AZ et l'Auto Scaling Group (1 à 4 EC2)"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# DONNÉES DU COMPTE & RÉSEAU PAR DÉFAUT
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
# 0. Service Cognito
module "auth_cognito" {
  source       = "./modules/00-auth-cognito"
  project_name = var.project_name
}

# ------------------------------------------------------------------------------
# APPEL DES 5 MODULES DU PROJET
# ------------------------------------------------------------------------------

# 1. Base de données DynamoDB (Catalogue & Commandes) + Bucket S3 (Factures PDF)
module "database_dynamodb" {
  source       = "./modules/01-database-dynamodb"
  project_name = var.project_name
  account_id   = data.aws_caller_identity.current.account_id
}

# 2. Messaging Événementiel (Topics SNS & File d'attente SQS)
module "messaging_sns_sqs" {
  source             = "./modules/02-messaging-sns-sqs"
  project_name       = var.project_name
  notification_email = var.notification_email
}

# 3. Cœur Serverless (Fonction AWS Lambda de prise de commande)
module "serverless_lambda" {
  source                       = "./modules/03-serverless-lambda"
  project_name                 = var.project_name
  aws_region                   = var.aws_region
  products_table_name          = module.database_dynamodb.products_table_name
  products_table_arn           = module.database_dynamodb.products_table_arn
  orders_table_name            = module.database_dynamodb.orders_table_name
  orders_table_arn             = module.database_dynamodb.orders_table_arn
  order_confirmation_topic_arn = module.messaging_sns_sqs.order_confirmation_topic_arn
  orders_batch_queue_url       = module.messaging_sns_sqs.orders_batch_queue_url
  orders_batch_queue_arn       = module.messaging_sns_sqs.orders_batch_queue_arn
}

# 4. Serveur Web Front-End EC2 (+ option ALB & Auto Scaling Group)
module "frontend_ec2" {
  source                          = "./modules/04-frontend-ec2"
  project_name                    = var.project_name
  aws_region                      = var.aws_region
  vpc_id                          = data.aws_vpc.default.id
  subnet_ids                      = data.aws_subnets.default.ids
  ami_id                          = data.aws_ami.al2023.id
  products_table_name             = module.database_dynamodb.products_table_name
  products_table_arn              = module.database_dynamodb.products_table_arn
  orders_table_name               = module.database_dynamodb.orders_table_name
  orders_table_arn                = module.database_dynamodb.orders_table_arn
  invoices_bucket_name            = module.database_dynamodb.invoices_bucket_name
  invoices_bucket_arn             = module.database_dynamodb.invoices_bucket_arn
  lambda_function_name            = module.serverless_lambda.lambda_function_name
  lambda_function_arn             = module.serverless_lambda.lambda_function_arn
  order_confirmation_topic_arn    = module.messaging_sns_sqs.order_confirmation_topic_arn
  shipping_notification_topic_arn = module.messaging_sns_sqs.shipping_notification_topic_arn
  orders_batch_queue_url          = module.messaging_sns_sqs.orders_batch_queue_url
  orders_batch_queue_arn          = module.messaging_sns_sqs.orders_batch_queue_arn
  spot_launch_template_id         = module.batch_ec2_spot.spot_launch_template_id
  spot_worker_role_arn            = module.batch_ec2_spot.spot_worker_role_arn
  enable_autoscaling_alb          = var.enable_autoscaling_alb
  user_pool_id        = module.auth_cognito.user_pool_id
  user_pool_client_id = module.auth_cognito.user_pool_client_id
}

# 5. Worker Batch EC2 Spot (Périodique + lancement à la demande + auto-destruction)
module "batch_ec2_spot" {
  source                          = "./modules/05-batch-ec2-spot"
  project_name                    = var.project_name
  aws_region                      = var.aws_region
  vpc_id                          = data.aws_vpc.default.id
  subnet_id                       = data.aws_subnets.default.ids[0]
  ami_id                          = data.aws_ami.al2023.id
  orders_table_name               = module.database_dynamodb.orders_table_name
  orders_table_arn                = module.database_dynamodb.orders_table_arn
  invoices_bucket_name            = module.database_dynamodb.invoices_bucket_name
  invoices_bucket_arn             = module.database_dynamodb.invoices_bucket_arn
  orders_batch_queue_url          = module.messaging_sns_sqs.orders_batch_queue_url
  orders_batch_queue_arn          = module.messaging_sns_sqs.orders_batch_queue_arn
  shipping_notification_topic_arn = module.messaging_sns_sqs.shipping_notification_topic_arn
  order_confirmation_topic_arn    = module.messaging_sns_sqs.order_confirmation_topic_arn
}

# ------------------------------------------------------------------------------
# SORTIES (OUTPUTS)
# ------------------------------------------------------------------------------
output "website_url" {
  description = "URL publique de la boutique CloudShop"
  value       = module.frontend_ec2.website_url
}

output "front_instance_id" {
  description = "Identifiant de l'instance EC2 Front-End (ou Auto Scaling Group)"
  value       = module.frontend_ec2.front_instance_id
}

output "spot_launch_template_id" {
  description = "Identifiant du Launch Template EC2 Spot (Périodique & Lancement à la demande)"
  value       = module.batch_ec2_spot.spot_launch_template_id
}

output "dynamodb_tables" {
  description = "Tables DynamoDB créées"
  value = {
    products = module.database_dynamodb.products_table_name
    orders   = module.database_dynamodb.orders_table_name
  }
}

output "s3_invoices_bucket" {
  description = "Bucket S3 stockant les factures PDF générées"
  value       = module.database_dynamodb.invoices_bucket_name
}

output "sns_topics" {
  description = "Topics SNS de notification"
  value = {
    order_confirmation    = module.messaging_sns_sqs.order_confirmation_topic_arn
    shipping_notification = module.messaging_sns_sqs.shipping_notification_topic_arn
  }
}

output "sqs_batch_queue_url" {
  description = "File d'attente SQS alimentant le Worker EC2 Spot"
  value       = module.messaging_sns_sqs.orders_batch_queue_url
}
