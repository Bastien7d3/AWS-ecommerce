output "user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.pool.arn
}

output "admin_group_name" {
  value = aws_cognito_user_group.admin.name
}
