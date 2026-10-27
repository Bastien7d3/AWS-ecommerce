variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "ami_id" {
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

variable "orders_batch_queue_url" {
  type = string
}

variable "orders_batch_queue_arn" {
  type = string
}

variable "shipping_notification_topic_arn" {
  type = string
}

variable "order_confirmation_topic_arn" {
  type = string
}
