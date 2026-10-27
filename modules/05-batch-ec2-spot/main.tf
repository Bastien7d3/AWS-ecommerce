# ==============================================================================
# MODULE 05 : WORKER BATCH EC2 SPOT (CALCUL COLIS, FACTURE PDF S3 & SUIVI SNS)
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
}

resource "aws_s3_object" "batch_worker_script" {
  bucket  = var.invoices_bucket_name
  key     = "scripts/batch_worker.py"
  content = local.rendered_worker_py
}

resource "aws_instance" "spot_worker" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.spot_worker_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.spot_worker_profile.name
  associate_public_ip_address = true

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type = "one-time"
    }
  }

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
#!/bin/bash
set -e
exec > /var/log/spot_worker.log 2>&1

dnf install -y python3-pip python3-boto3
pip3 install boto3 fpdf2

aws s3 cp s3://${var.invoices_bucket_name}/scripts/batch_worker.py /opt/batch_worker.py --region ${var.aws_region}
chmod +x /opt/batch_worker.py

cat << 'SERVICE_EOF' > /etc/systemd/system/cloudshop-spot-worker.service
[Unit]
Description=CloudShop Batch Spot Worker (PDF & Carrier Box Sizing)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/batch_worker.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable --now cloudshop-spot-worker.service
EOF

  tags = {
    Name = "${var.project_name}-spot-batch-worker"
  }

  depends_on = [
    aws_iam_role_policy.spot_worker_policy,
    aws_s3_object.batch_worker_script
  ]
}
