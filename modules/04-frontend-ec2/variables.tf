variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "ami_id" {
  type = string
}

variable "products_table_name" {
  type = string
}

variable "products_table_arn" {
  type = string
}

variable "orders_table_name" {
  type = string
}

variable "orders_table_arn" {
  type = string
}

variable "invoices_bucket_name" {
  type = string
}

variable "invoices_bucket_arn" {
  type = string
}

variable "lambda_function_name" {
  type = string
}

variable "lambda_function_arn" {
  type = string
}

variable "enable_autoscaling_alb" {
  description = "Active l'Application Load Balancer Multi-AZ et l'Auto Scaling Group (1 à 4 instances)"
  type        = bool
  default     = false
}
