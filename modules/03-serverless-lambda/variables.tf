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

variable "user_pool_id" {
  type    = string
  default = ""
}

variable "user_pool_client_id" {
  type    = string
  default = ""
}

variable "user_pool_arn" {
  type    = string
  default = ""
}
