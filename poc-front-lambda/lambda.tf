# ==============================================================================
# RÔLE IAM & FONCTION LAMBDA (Serverless)
# ==============================================================================

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/lambda_function.py"
  output_path = "${path.module}/lambda_src/lambda.zip"
}

resource "aws_lambda_function" "test_lambda" {
  function_name    = "${var.project_name}-demo"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  description = "Fonction Lambda de test invoquée depuis l'instance EC2 Front-End"
}
