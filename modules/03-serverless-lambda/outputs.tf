output "lambda_function_name" {
  value = aws_lambda_function.create_order.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.create_order.arn
}
