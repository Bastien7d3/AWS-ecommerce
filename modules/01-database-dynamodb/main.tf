# ==============================================================================
# MODULE 01 : BASE DE DONNÉES DYNAMODB (CATALOGUE & COMMANDES) + BUCKET S3 (PDF)
# ==============================================================================

# 1. Table du Catalogue Produits (100% Always Free : Mode PROVISIONED 5 RCU / 5 WCU)
resource "aws_dynamodb_table" "products" {
  name           = "${var.project_name}-products"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "product_id"

  attribute {
    name = "product_id"
    type = "S"
  }
}

# Articles initiaux pré-insérés dans le catalogue pour la boutique
locals {
  initial_products = {
    "PROD-01" = {
      product_id = { S = "PROD-01" }
      name       = { S = "Clavier Mecanique CloudPro RGB" }
      price_eur  = { N = "89.90" }
      stock      = { N = "15" }
      dims_cm    = { S = "36x14x4" }
      weight_kg  = { N = "0.95" }
    }
    "PROD-02" = {
      product_id = { S = "PROD-02" }
      name       = { S = "Casque Audio Studio Sans-Fil" }
      price_eur  = { N = "64.50" }
      stock      = { N = "25" }
      dims_cm    = { S = "22x18x10" }
      weight_kg  = { N = "0.45" }
    }
    "PROD-03" = {
      product_id = { S = "PROD-03" }
      name       = { S = "Support Ecran Ergonomique Alu" }
      price_eur  = { N = "45.00" }
      stock      = { N = "10" }
      dims_cm    = { S = "35x22x8" }
      weight_kg  = { N = "1.80" }
    }
  }
}

resource "aws_dynamodb_table_item" "seed_products" {
  for_each   = local.initial_products
  table_name = aws_dynamodb_table.products.name
  hash_key   = aws_dynamodb_table.products.hash_key
  item       = jsonencode(each.value)
}

# 2. Table des Commandes & Suivi d'Audit (100% Always Free : 5 RCU / 5 WCU)
resource "aws_dynamodb_table" "orders" {
  name           = "${var.project_name}-orders"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}

# 3. Bucket S3 pour stocker les Factures PDF et les Rapports d'Audit générés par l'EC2 Spot
resource "aws_s3_bucket" "invoices" {
  bucket        = "${var.project_name}-invoices-${var.account_id}"
  force_destroy = true # Permet à 'terraform destroy' de vider et supprimer le bucket sans erreur
}
