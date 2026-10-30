resource "aws_cognito_user_pool" "pool" {
  name                     = "${var.project_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Code de confirmation NEOLIA"
    email_message        = "Bienvenue sur NEOLIA ! Votre code de confirmation est : {####}"
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true
  }

  lifecycle {
    ignore_changes = [schema]
  }
}

# ------------------------------------------------------------------------------
# GROUPE UTILISATEUR ADMIN COGNITO
# ------------------------------------------------------------------------------
resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.pool.id
  description  = "Groupe administrateurs CloudShop"
  precedence   = 1
}

# ------------------------------------------------------------------------------
# DOMAINE COGNITO (Unicité garantie par compte pour éviter tout conflit inter-comptes)
# ------------------------------------------------------------------------------
resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.account_id != "" ? "${var.project_name}-auth-${var.account_id}" : "${var.project_name}-auth-fisa2026"
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_cognito_user_pool_client" "client" {
  name            = "${var.project_name}-app-client"
  user_pool_id    = aws_cognito_user_pool.pool.id
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]
}
