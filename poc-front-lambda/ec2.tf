# ==============================================================================
# RÉSEAU PAR DÉFAUT & SÉCURITÉ
# ==============================================================================

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

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Autorise le trafic HTTP entrant sur le port 80 et tout le trafic sortant"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP entrant pour les visiteurs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Trafic sortant vers les API AWS (Lambda, etc.) et mises a jour"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

# ==============================================================================
# RÔLE IAM INSTANCE EC2 (Autorise l'appel vers la Lambda)
# ==============================================================================

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "ec2_invoke_lambda_policy" {
  name        = "${var.project_name}-ec2-invoke-lambda"
  description = "Autorise le serveur web EC2 a invoquer la fonction Lambda de test"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [aws_lambda_function.test_lambda.arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_invoke" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_invoke_lambda_policy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# ==============================================================================
# INSTANCE EC2 (Front-End Web)
# ==============================================================================

locals {
  server_script = templatefile("${path.module}/server_src/server.py.tftpl", {
    region      = var.aws_region
    lambda_name = aws_lambda_function.test_lambda.function_name
  })
}

resource "aws_instance" "web_front" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
#!/bin/bash
set -e
exec > /var/log/user_data_front.log 2>&1

echo "=== [1/3] Installation de Boto3 ==="
dnf install -y python3-pip python3-boto3 || pip3 install boto3

echo "=== [2/3] Configuration du script Serveur Web ==="
echo "${base64encode(local.server_script)}" | base64 -d > /opt/server.py
chmod +x /opt/server.py

echo "=== [3/3] Creation du service Systemd pour le serveur web ==="
cat << 'SERVICE_EOF' > /etc/systemd/system/cloudshop-web.service
[Unit]
Description=CloudShop Front-End Web Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt
ExecStart=/usr/bin/python3 /opt/server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable --now cloudshop-web.service
echo "=== Deploiement termine avec succes ! ==="
EOF

  tags = {
    Name = "${var.project_name}-front-server"
  }

  depends_on = [
    aws_lambda_function.test_lambda,
    aws_iam_role_policy_attachment.attach_invoke
  ]
}
