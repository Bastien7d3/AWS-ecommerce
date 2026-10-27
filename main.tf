# ==============================================================================
# ORCHESTRATION GLOBALE DU PROJET CLOUDSHOP AWS (FISA 2026)
# Connecte les 5 briques : DynamoDB/S3 <-> SNS/SQS <-> Lambda <-> EC2 Front <-> EC2 Spot
# ==============================================================================

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
  source                 = "./modules/04-frontend-ec2"
  project_name           = var.project_name
  aws_region             = var.aws_region
  vpc_id                 = data.aws_vpc.default.id
  subnet_ids             = data.aws_subnets.default.ids
  ami_id                 = data.aws_ami.al2023.id
  products_table_name    = module.database_dynamodb.products_table_name
  products_table_arn     = module.database_dynamodb.products_table_arn
  orders_table_name      = module.database_dynamodb.orders_table_name
  orders_table_arn       = module.database_dynamodb.orders_table_arn
  invoices_bucket_name   = module.database_dynamodb.invoices_bucket_name
  invoices_bucket_arn    = module.database_dynamodb.invoices_bucket_arn
  lambda_function_name   = module.serverless_lambda.lambda_function_name
  lambda_function_arn    = module.serverless_lambda.lambda_function_arn
  enable_autoscaling_alb = var.enable_autoscaling_alb
}

# 5. Worker Batch EC2 Spot (Calcul colis S/M/L/XL, génération Facture PDF S3 & suivi SNS)
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
}
