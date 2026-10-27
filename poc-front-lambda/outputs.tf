output "ec2_public_ip" {
  description = "Adresse IP publique de l'instance EC2"
  value       = aws_instance.web_front.public_ip
}

output "website_url" {
  description = "URL pour acceder au site web de test depuis votre navigateur"
  value       = "http://${aws_instance.web_front.public_ip}"
}

output "lambda_name" {
  description = "Nom de la fonction Lambda invoquee par le bouton"
  value       = aws_lambda_function.test_lambda.function_name
}
