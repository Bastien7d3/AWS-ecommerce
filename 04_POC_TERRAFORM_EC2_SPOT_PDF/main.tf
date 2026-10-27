terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CloudShop-FISA2026-PoC"
      Environment = "PoC-Spot-PDF"
      ManagedBy   = "Terraform"
    }
  }
}

# ==============================================================================
# VARIABLES (Parametrables par l'Admin Cloud)
# ==============================================================================
variable "aws_region" {
  description = "Region AWS cible"
  type        = string
  default     = "eu-west-3"
}

variable "admin_spot_trigger_threshold" {
  description = "Seuil Admin Cloud : nombre de commandes en file SQS pour demarrer 1 instance EC2 Spot"
  type        = number
  default     = 10
}

variable "admin_spot_split_threshold" {
  description = "Seuil Admin Cloud (Pic de charge) : nombre de commandes pour splitter le batch sur 2 instances EC2 Spot"
  type        = number
  default     = 50
}

# ==============================================================================
# DATA SOURCES (Compte, VPC par defaut, AMI Amazon Linux 2023)
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

# ==============================================================================
# 1. STOCKAGE & BASE DE DONNEES (S3 Factures PDF + DynamoDB Commandes)
# ==============================================================================
resource "aws_s3_bucket" "invoices" {
  bucket        = "poc-cloudshop-invoices-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_dynamodb_table" "orders" {
  name           = "poc-cloudshop-orders"
  billing_mode   = "PROVISIONED" # 100% Always Free (<= 25 RCU / 25 WCU)
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}

# Commande initiale au statut PENDING dans DynamoDB
resource "aws_dynamodb_table_item" "sample_order" {
  table_name = aws_dynamodb_table.orders.name
  hash_key   = aws_dynamodb_table.orders.hash_key

  item = jsonencode({
    order_id         = { S = "CMD-2026-001" }
    customer_name    = { S = "Bastien - FISA 2026" }
    status           = { S = "PENDING" }
    shipping_address = { S = "12 Rue de la Paix, 75002 Paris" }
    created_at       = { S = "2026-10-26T15:35:00Z" }
  })
}

# ==============================================================================
# 2. MESSAGING & SURVEILLANCE CLOUDWATCH (SQS + SNS + Alarmes Admin)
# ==============================================================================
resource "aws_sqs_queue" "orders_batch" {
  name                       = "poc-orders-batch-queue"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
}

resource "aws_sns_topic" "shipping_notifications" {
  name = "poc-order-shipped-topic"
}

# Alarme 1 : Seuil normal defini par l'Admin Cloud pour lancer le batch Spot
resource "aws_cloudwatch_metric_alarm" "spot_trigger_alarm" {
  alarm_name          = "CloudShop-SQS-Batch-Start-Threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = var.admin_spot_trigger_threshold
  alarm_description   = "Declenche 1 Worker EC2 Spot lorsque le nombre de commandes en attente depasse le seuil Admin (${var.admin_spot_trigger_threshold})"

  dimensions = {
    QueueName = aws_sqs_queue.orders_batch.name
  }
}

# Alarme 2 : Seuil de pic defini par l'Admin Cloud pour splitter le batch en 2
resource "aws_cloudwatch_metric_alarm" "spot_split_alarm" {
  alarm_name          = "CloudShop-SQS-Batch-Split-Surge-Threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = var.admin_spot_split_threshold
  alarm_description   = "Pic de commandes (> ${var.admin_spot_split_threshold}) : lance une 2eme instance EC2 Spot pour splitter le batch SQS en 2"

  dimensions = {
    QueueName = aws_sqs_queue.orders_batch.name
  }
}

# ==============================================================================
# 3. SECURITE IAM & SECURITY GROUP (Moindre Privilege)
# ==============================================================================
resource "aws_iam_role" "spot_worker_role" {
  name = "poc-cloudshop-spot-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "spot_worker_policy" {
  name = "poc-cloudshop-spot-worker-policy"
  role = aws_iam_role.spot_worker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.orders_batch.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.invoices.arn, "${aws_s3_bucket.invoices.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem", "dynamodb:PutItem"]
        Resource = aws_dynamodb_table.orders.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.shipping_notifications.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "spot_worker_profile" {
  name = "poc-cloudshop-spot-worker-profile"
  role = aws_iam_role.spot_worker_role.name
}

resource "aws_security_group" "spot_worker_sg" {
  name        = "poc-cloudshop-spot-worker-sg"
  description = "Aucun port entrant ouvert - Sortie HTTPS uniquement vers les API AWS"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==============================================================================
# 4. INSTANCE EC2 SPOT (t3.micro) - GENERATION PDF & DIMENSIONNEMENT COLIS
# ==============================================================================
locals {
  worker_py = templatefile("${path.module}/worker.py.tftpl", {
    region        = var.aws_region
    sqs_queue_url = aws_sqs_queue.orders_batch.id
    s3_bucket     = aws_s3_bucket.invoices.bucket
    ddb_table     = aws_dynamodb_table.orders.name
    sns_topic_arn = aws_sns_topic.shipping_notifications.arn
  })

  sample_order_payload = jsonencode({
    order_id         = "CMD-2026-001"
    customer_name    = "Bastien - FISA 2026"
    shipping_address = "12 Rue de la Paix, 75002 Paris"
    items = [
      {
        name      = "Clavier Mecanique CloudPro RGB"
        qty       = 1
        price_eur = 89.90
        dims_cm   = [36, 14, 4]
        weight_kg = 0.95
      },
      {
        name      = "Casque Audio Studio Sans-Fil"
        qty       = 2
        price_eur = 64.50
        dims_cm   = [22, 18, 10]
        weight_kg = 0.45
      },
      {
        name      = "Support Ecran Ergonomique Alu"
        qty       = 1
        price_eur = 45.00
        dims_cm   = [35, 22, 8]
        weight_kg = 1.80
      }
    ]
  })
}

resource "aws_s3_object" "worker_script" {
  bucket  = aws_s3_bucket.invoices.id
  key     = "scripts/worker.py"
  content = local.worker_py
}

resource "aws_s3_object" "sample_order_json" {
  bucket  = aws_s3_bucket.invoices.id
  key     = "scripts/sample_order.json"
  content = local.sample_order_payload
}

resource "aws_instance" "spot_pdf_worker" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.spot_worker_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.spot_worker_profile.name
  associate_public_ip_address = true

  # Tarification EC2 Spot (jusqu'a -90% pour le batch asynchrone)
  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type = "one-time"
    }
  }

  # Disque EBS 8 Go gp3 (reste largement dans les 30 Go du Free Tier)
  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
#!/bin/bash
set -e
exec > /var/log/spot_worker_poc.log 2>&1

dnf install -y python3-pip
pip3 install boto3 fpdf2

aws s3 cp s3://${aws_s3_bucket.invoices.bucket}/scripts/sample_order.json /opt/sample_order.json --region ${var.aws_region}
aws s3 cp s3://${aws_s3_bucket.invoices.bucket}/scripts/worker.py /opt/worker.py --region ${var.aws_region}

aws sqs send-message \
  --queue-url "${aws_sqs_queue.orders_batch.id}" \
  --message-body file:///opt/sample_order.json \
  --region ${var.aws_region}

python3 /opt/worker.py
EOF

  tags = {
    Name = "poc-cloudshop-spot-pdf-worker"
  }

  depends_on = [
    aws_dynamodb_table_item.sample_order,
    aws_iam_role_policy.spot_worker_policy,
    aws_s3_object.worker_script,
    aws_s3_object.sample_order_json
  ]
}

# ==============================================================================
# OUTPUTS
# ==============================================================================
output "spot_instance_id" {
  description = "ID de l'instance EC2 Spot lancee"
  value       = aws_instance.spot_pdf_worker.id
}

output "s3_invoices_bucket" {
  description = "Bucket S3 contenant la facture PDF generee"
  value       = aws_s3_bucket.invoices.bucket
}

output "sqs_queue_url" {
  description = "URL de la file SQS des commandes batch"
  value       = aws_sqs_queue.orders_batch.id
}

output "sns_topic_arn" {
  description = "ARN du Topic SNS de notification d'expedition"
  value       = aws_sns_topic.shipping_notifications.arn
}

output "cloudwatch_alarms" {
  description = "Alarmes CloudWatch de surveillance du seuil de commandes"
  value = {
    start_batch_alarm = aws_cloudwatch_metric_alarm.spot_trigger_alarm.alarm_name
    split_batch_alarm = aws_cloudwatch_metric_alarm.spot_split_alarm.alarm_name
  }
}
