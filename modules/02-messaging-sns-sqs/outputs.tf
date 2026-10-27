output "order_confirmation_topic_arn" {
  value = aws_sns_topic.order_confirmation.arn
}

output "shipping_notification_topic_arn" {
  value = aws_sns_topic.shipping_notification.arn
}

output "orders_batch_queue_url" {
  value = aws_sqs_queue.orders_batch.id
}

output "orders_batch_queue_arn" {
  value = aws_sqs_queue.orders_batch.arn
}
