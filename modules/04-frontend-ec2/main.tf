# ==============================================================================
# MODULE 04 : SERVEUR WEB FRONT-END EC2 (+ OPTION AUTO SCALING & ALB MULTI-AZ)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. SECURITY GROUPS (Séparation ALB Public & EC2 Privées/Protégées)
# ------------------------------------------------------------------------------
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-front-web-sg"
  description = "Autorise le trafic HTTP entrant sur le port 80"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP entrant public"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Sortie vers les API AWS (Lambda, DynamoDB, S3, SNS, SQS, EC2)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------------------
# 2. RÔLE & POLICIES IAM (Indispensables pour que le Web Server appelle AWS)
# ------------------------------------------------------------------------------
resource "aws_iam_role" "front_ec2_role" {
  name = "${var.project_name}-front-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "front_ec2_policy" {
  name = "${var.project_name}-front-ec2-policy"
  role = aws_iam_role.front_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Scan", "dynamodb:GetItem", "dynamodb:Query"]
        Resource = [var.products_table_arn, var.orders_table_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [var.lambda_function_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [var.invoices_bucket_arn, "${var.invoices_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Subscribe", "sns:SetSubscriptionAttributes"]
        Resource = [var.order_confirmation_topic_arn, var.shipping_notification_topic_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:GetQueueAttributes"]
        Resource = [var.orders_batch_queue_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:RunInstances", "ec2:DescribeInstances", "ec2:CreateTags", "ec2:RequestSpotInstances", "ec2:DescribeSubnets"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [var.spot_worker_role_arn]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "front_ec2_profile" {
  name = "${var.project_name}-front-ec2-profile"
  role = aws_iam_role.front_ec2_role.name
}

# ------------------------------------------------------------------------------
# 3. SCRIPTS ET PROVISIONING (Génération du script Python et upload S3)
# ------------------------------------------------------------------------------
locals {
  rendered_server_py = templatefile("${path.module}/src/app_server.py.tftpl", {
    region          = var.aws_region
    products_table  = var.products_table_name
    orders_table    = var.orders_table_name
    invoices_bucket = var.invoices_bucket_name
    lambda_name      = var.lambda_function_name
    sns_confirm_arn = var.order_confirmation_topic_arn
    sns_ship_arn    = var.shipping_notification_topic_arn
    sqs_queue_url   = var.orders_batch_queue_url
    spot_lt_id      = var.spot_launch_template_id
    user_pool_id        = var.user_pool_id
    user_pool_client_id = var.user_pool_client_id
  })

  front_user_data = <<-EOF
#!/bin/bash
# Script hash: ${md5(local.rendered_server_py)}
set -e
exec > /var/log/front_server.log 2>&1

dnf install -y python3-pip python3-boto3 || pip3 install boto3
aws s3 cp s3://${var.invoices_bucket_name}/scripts/app_server.py /opt/app_server.py --region ${var.aws_region}
chmod +x /opt/app_server.py

cat << 'SERVICE_EOF' > /etc/systemd/system/cloudshop-front.service
[Unit]
Description=CloudShop Front-End Web Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/app_server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable --now cloudshop-front.service
EOF
}

resource "aws_s3_object" "front_server_script" {
  bucket  = var.invoices_bucket_name
  key     = "scripts/app_server.py"
  content = local.rendered_server_py
}

# ------------------------------------------------------------------------------
# MODE 1 (Par défaut) : Instance EC2 Front-End unique et rapide
# ------------------------------------------------------------------------------
resource "aws_instance" "web_front_single" {
  count                       = var.enable_autoscaling_alb ? 0 : 1
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = var.subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.front_ec2_profile.name
  associate_public_ip_address = true
  user_data                   = local.front_user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-front-ec2"
  }

  depends_on = [
    aws_iam_role_policy.front_ec2_policy,
    aws_s3_object.front_server_script
  ]
}

# ------------------------------------------------------------------------------
# MODE 2 (Si enable_autoscaling_alb = true) : ALB Multi-AZ + Auto Scaling Group
# ------------------------------------------------------------------------------
resource "aws_lb" "front_alb" {
  count              = var.enable_autoscaling_alb ? 1 : 0
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = slice(var.subnet_ids, 0, min(2, length(var.subnet_ids)))
}

resource "aws_lb_target_group" "front_tg" {
  count    = var.enable_autoscaling_alb ? 1 : 0
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }
}

resource "aws_lb_listener" "front_http" {
  count             = var.enable_autoscaling_alb ? 1 : 0
  load_balancer_arn = aws_lb.front_alb[0].arn
  port              = 80
  protocol          = "HTTP"

  # Bloque les accès directs à l'ALB : seul le trafic contenant le header secret CloudFront (règle prio 10) est forwardé
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Acces direct interdit : veuillez passer par le CDN CloudFront."
      status_code  = "403"
    }
  }
}

resource "aws_launch_template" "front_lt" {
  count         = var.enable_autoscaling_alb ? 1 : 0
  name_prefix   = "${var.project_name}-front-lt-"
  image_id      = var.ami_id
  instance_type = "t3.micro"
  user_data     = base64encode(local.front_user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.front_ec2_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  depends_on = [
    aws_s3_object.front_server_script
  ]
}

resource "aws_autoscaling_group" "front_asg" {
  count               = var.enable_autoscaling_alb ? 1 : 0
  name                = "${var.project_name}-front-asg"
  min_size            = 2
  desired_capacity    = 2
  max_size            = 4
  vpc_zone_identifier = slice(var.subnet_ids, 0, min(2, length(var.subnet_ids)))
  target_group_arns   = [aws_lb_target_group.front_tg[0].arn]

  # Utilise le bilan de santé de l ALB pour détecter une instance KO
  health_check_type         = "ELB"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.front_lt[0].id
    version = "$Latest"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  count                  = var.enable_autoscaling_alb ? 1 : 0
  name                   = "${var.project_name}-cpu-scaling-60"
  autoscaling_group_name = aws_autoscaling_group.front_asg[0].name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}

# ------------------------------------------------------------------------------
# 5. DISTRIBUTION CLOUDFRONT (CDN Edge + HTTPS)
# ------------------------------------------------------------------------------
moved {
  from = aws_cloudfront_distribution.front_cdn
  to   = aws_cloudfront_distribution.front_cdn[0]
}

resource "aws_cloudfront_distribution" "front_cdn" {
  count               = var.enable_autoscaling_alb ? 1 : 0
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CDN CloudShop pour le Load Balancer"
  price_class         = "PriceClass_100"

  origin {
    domain_name = aws_lb.front_alb[0].dns_name
    origin_id   = "ALB-CloudShop"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Optionnel : Envoi du header secret pour sécuriser l'ALB
    custom_header {
      name  = "X-CloudFront-Secret"
      value = "MonSecretCloudShop2026"
    }
  }

  default_cache_behavior {
    target_origin_id       = "ALB-CloudShop"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "aws_lb_listener_rule" "require_cloudfront_header" {
  count        = var.enable_autoscaling_alb ? 1 : 0
  listener_arn = aws_lb_listener.front_http[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front_tg[0].arn
  }

  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = ["MonSecretCloudShop2026"]
    }
  }
}
