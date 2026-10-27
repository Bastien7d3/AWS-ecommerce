# ==============================================================================
# MODULE 05 : WORKER BATCH EC2 SPOT À LA DEMANDE & PÉRIODIQUE (0 INSTANCE AU REPOS)
# ==============================================================================

resource "aws_security_group" "spot_worker_sg" {
  name        = "${var.project_name}-spot-worker-sg"
  description = "Aucun port entrant ouvert - Sortie vers les API AWS (SQS, S3, DynamoDB, SNS)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "spot_worker_role" {
  name = "${var.project_name}-spot-worker-role"

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
  name = "${var.project_name}-spot-worker-policy"
  role = aws_iam_role.spot_worker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = var.orders_batch_queue_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [var.invoices_bucket_arn, "${var.invoices_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
        Resource = var.orders_table_arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = var.shipping_notification_topic_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "spot_worker_profile" {
  name = "${var.project_name}-spot-worker-profile"
  role = aws_iam_role.spot_worker_role.name
}

locals {
  rendered_worker_py = templatefile("${path.module}/src/batch_worker.py.tftpl", {
    region           = var.aws_region
    sqs_queue_url    = var.orders_batch_queue_url
    s3_bucket        = var.invoices_bucket_name
    orders_table     = var.orders_table_name
    sns_shipping_arn = var.shipping_notification_topic_arn
  })

  spot_user_data = <<-EOF
#!/bin/bash
set -e
exec > /var/log/spot_worker.log 2>&1

dnf install -y python3-pip python3-boto3
pip3 install boto3 fpdf2

aws s3 cp s3://${var.invoices_bucket_name}/scripts/batch_worker.py /opt/batch_worker.py --region ${var.aws_region}
chmod +x /opt/batch_worker.py

# Exécute le batch SQS -> PDF -> S3 -> DynamoDB -> SNS puis éteint/détruit l'instance Spot !
python3 /opt/batch_worker.py
EOF
}

resource "aws_s3_object" "batch_worker_script" {
  bucket  = var.invoices_bucket_name
  key     = "scripts/batch_worker.py"
  content = local.rendered_worker_py
}

# 1. Modèle de lancement (Launch Template) de l'EC2 Spot avec auto-destruction à l'arrêt
resource "aws_launch_template" "spot_worker_lt" {
  name                                 = "${var.project_name}-spot-worker-lt"
  image_id                             = var.ami_id
  instance_type                        = "t3.micro"
  instance_initiated_shutdown_behavior = "terminate" # Quand le script fait 'shutdown -h now', l'instance est détruite !
  user_data                            = base64encode(local.spot_user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.spot_worker_profile.name
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type = "one-time"
    }
  }

  network_interfaces {
    associate_public_ip_address = true
    subnet_id                   = var.subnet_id
    security_groups             = [aws_security_group.spot_worker_sg.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-spot-batch-worker"
      Role = "spot-batch-worker"
    }
  }

  depends_on = [
    aws_iam_role_policy.spot_worker_policy,
    aws_s3_object.batch_worker_script
  ]
}

# 2. Planification périodique nocturne (0 instance au repos, lance 1 Spot à 02h00 UTC)
resource "aws_autoscaling_group" "spot_periodic_asg" {
  name                = "${var.project_name}-spot-periodic-asg"
  min_size            = 0
  desired_capacity    = 0 # 0 instance allumée par défaut !
  max_size            = 1
  vpc_zone_identifier = [var.subnet_id]

  launch_template {
    id      = aws_launch_template.spot_worker_lt.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_schedule" "nightly_batch_start" {
  scheduled_action_name  = "${var.project_name}-nightly-02h00-batch"
  min_size               = 0
  max_size               = 1
  desired_capacity       = 1
  recurrence             = "0 2 * * *" # Tous les jours à 02h00 du matin
  autoscaling_group_name = aws_autoscaling_group.spot_periodic_asg.name
}
