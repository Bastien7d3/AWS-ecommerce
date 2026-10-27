output "products_table_name" {
  value = aws_dynamodb_table.products.name
}

output "products_table_arn" {
  value = aws_dynamodb_table.products.arn
}

output "orders_table_name" {
  value = aws_dynamodb_table.orders.name
}

output "orders_table_arn" {
  value = aws_dynamodb_table.orders.arn
}

output "invoices_bucket_name" {
  value = aws_s3_bucket.invoices.bucket
}

output "invoices_bucket_arn" {
  value = aws_s3_bucket.invoices.arn
}
