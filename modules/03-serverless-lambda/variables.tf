variable "project_name" {
  type = string
}

variable "aws_region" {
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

variable "order_confirmation_topic_arn" {
  type = string
}

variable "orders_batch_queue_url" {
  type = string
}

variable "orders_batch_queue_arn" {
  type = string
}
