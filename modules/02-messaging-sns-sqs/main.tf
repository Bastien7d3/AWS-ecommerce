# ==============================================================================
# MODULE 02 : MESSAGING ÉVÉNEMENTIEL (AMAZON SNS & AMAZON SQS)
# ==============================================================================

# 1. Topic SNS : Confirmation immédiate de commande (alimenté par la Lambda)
resource "aws_sns_topic" "order_confirmation" {
  name = "${var.project_name}-order-confirmation"
}

# 2. Topic SNS : Notification d'expédition + N° de Suivi + Lien PDF (alimenté par l'EC2 Spot)
resource "aws_sns_topic" "shipping_notification" {
  name = "${var.project_name}-shipping-notification"
}

# Abonnement e-mail optionnel (activé uniquement si var.notification_email est renseigné)
resource "aws_sns_topic_subscription" "email_order_confirm" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.order_confirmation.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_sns_topic_subscription" "email_shipping_notify" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.shipping_notification.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# 3. File d'attente SQS : Tampon résilient entre la Lambda et le Worker EC2 Spot
resource "aws_sqs_queue" "orders_batch" {
  name                       = "${var.project_name}-orders-batch-queue"
  visibility_timeout_seconds = 120
  message_retention_seconds  = 1209600 # 14 jours de rétention maximale en cas d'arrêt du batch
}
