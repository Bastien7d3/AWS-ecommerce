output "spot_launch_template_id" {
  description = "ID du Launch Template pour lancer une instance EC2 Spot à la demande"
  value       = aws_launch_template.spot_worker_lt.id
}

output "spot_launch_template_name" {
  description = "Nom du Launch Template EC2 Spot"
  value       = aws_launch_template.spot_worker_lt.name
}

output "spot_worker_role_arn" {
  description = "ARN du rôle IAM attaché au Worker Spot"
  value       = aws_iam_role.spot_worker_role.arn
}
