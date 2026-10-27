resource "aws_cognito_user_pool" "pool" {
  name                     = "${var.project_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  verification_message_template {
    default_email_option  = "CONFIRM_WITH_LINK"
    email_subject         = "Activation de votre compte CloudShop"
    email_message_by_link = "Merci de vous être inscrit sur CloudShop ! Veuillez cliquer sur le lien suivant pour confirmer votre compte : {##Cliquer ici##}"
  }

  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true
  }
}

# ------------------------------------------------------------------------------
# DOMAINE COGNITO (REQUIS POUR LA VALIDATION PAR LIEN EMAIL)
# ------------------------------------------------------------------------------
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-auth-fisa2026"
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
