output "website_url" {
  description = "URL publique de la boutique CloudShop"
  value       = module.frontend_ec2.website_url
}

output "front_instance_id" {
  description = "Identifiant de l'instance EC2 Front-End (ou Auto Scaling Group)"
  value       = module.frontend_ec2.front_instance_id
}

output "spot_worker_instance_id" {
  description = "Identifiant de l'instance EC2 Spot (Worker Batch PDF & Colisage)"
  value       = module.batch_ec2_spot.spot_worker_instance_id
}

output "dynamodb_tables" {
  description = "Tables DynamoDB créées"
  value = {
    products = module.database_dynamodb.products_table_name
    orders   = module.database_dynamodb.orders_table_name
  }
}

output "s3_invoices_bucket" {
  description = "Bucket S3 stockant les factures PDF générées"
  value       = module.database_dynamodb.invoices_bucket_name
}

output "sns_topics" {
  description = "Topics SNS de notification"
  value = {
    order_confirmation    = module.messaging_sns_sqs.order_confirmation_topic_arn
    shipping_notification = module.messaging_sns_sqs.shipping_notification_topic_arn
  }
}

output "sqs_batch_queue_url" {
  description = "File d'attente SQS alimentant le Worker EC2 Spot"
  value       = module.messaging_sns_sqs.orders_batch_queue_url
}
