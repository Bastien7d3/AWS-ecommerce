output "website_url" {
  value = var.enable_autoscaling_alb ? "http://${aws_lb.front_alb[0].dns_name}" : "http://${aws_instance.web_front_single[0].public_ip}"
}

output "front_instance_id" {
  value = var.enable_autoscaling_alb ? "Managed-by-ASG-${aws_autoscaling_group.front_asg[0].name}" : aws_instance.web_front_single[0].id
}
