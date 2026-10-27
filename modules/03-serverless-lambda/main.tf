# ==============================================================================
# MODULE 03 : FONCTION AWS LAMBDA (PRISE DE COMMANDE SERVERLESS)
# ==============================================================================

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-create-order-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Permissions au moindre privilège : DynamoDB (Products & Orders), SNS et SQS
resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${var.project_name}-create-order-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:PutItem"]
        Resource = [var.products_table_arn, var.orders_table_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = var.order_confirmation_topic_arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = var.orders_batch_queue_arn
      }
    ]
  })
}

data "archive_file" "create_order_zip" {
  type        = "zip"
  source_file = "${path.module}/src/create_order.py"
  output_path = "${path.module}/src/create_order.zip"
}

resource "aws_lambda_function" "create_order" {
  function_name    = "${var.project_name}-create-order"
  role             = aws_iam_role.lambda_role.arn
  handler          = "create_order.lambda_handler"
  runtime          = "python3.12"
  timeout          = 15
  memory_size      = 128
  filename         = data.archive_file.create_order_zip.output_path
  source_code_hash = data.archive_file.create_order_zip.output_base64sha256

  environment {
    variables = {
      AWS_REGION_TARGET = var.aws_region
      PRODUCTS_TABLE    = var.products_table_name
      ORDERS_TABLE      = var.orders_table_name
      SNS_CONFIRM_ARN   = var.order_confirmation_topic_arn
      SQS_BATCH_URL     = var.orders_batch_queue_url
    }
  }
}
