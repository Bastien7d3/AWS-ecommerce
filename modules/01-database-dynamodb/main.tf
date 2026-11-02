
# ==============================================================================
# MODULE 01 : DYNAMODB (CATALOGUE & COMMANDES) + BUCKET S3 (PDF)
# ==============================================================================

# 1. Table du catalogue produits
# Conserve le nom existant : ${var.project_name}-products
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

  tags = {
    Project = var.project_name
    Brand   = "ATELIER NOIR"
    Purpose = "Catalogue cosmetiques"
  }
}

# 2. Catalogue initial ATELIER NOIR
# Les catégories doivent rester en minuscules pour le frontend.
locals {
  initial_products = {
    "ATN-VIS-001" = {
      product_id = { S = "ATN-VIS-001" }
      category   = { S = "visage" }
      name       = { S = "Gel Nettoyant Minéral" }
      description = { S = "Nettoyant doux aux minéraux, pour une peau nette sans sensation de tiraillement." }
      price_eur  = { N = "24.00" }
      stock      = { N = "30" }
      dims_cm    = { S = "5x5x16" }
      weight_kg  = { N = "0.22" }
    }

    "ATN-VIS-002" = {
      product_id = { S = "ATN-VIS-002" }
      category   = { S = "visage" }
      name       = { S = "Sérum Équilibre Niacinamide" }
      description = { S = "Sérum léger pour aider à uniformiser l'apparence du teint." }
      price_eur  = { N = "42.00" }
      stock      = { N = "18" }
      dims_cm    = { S = "4x4x12" }
      weight_kg  = { N = "0.12" }
    }

    "ATN-VIS-003" = {
      product_id = { S = "ATN-VIS-003" }
      category   = { S = "visage" }
      name       = { S = "Crème Hydratante Signature" }
      description = { S = "Hydratation quotidienne au fini discret et non gras." }
      price_eur  = { N = "36.00" }
      stock      = { N = "24" }
      dims_cm    = { S = "6x6x7" }
      weight_kg  = { N = "0.18" }
    }

    "ATN-VIS-004" = {
      product_id = { S = "ATN-VIS-004" }
      category   = { S = "visage" }
      name       = { S = "Contour des Yeux Réveil" }
      description = { S = "Soin frais pour le contour des yeux, à utiliser matin et soir." }
      price_eur  = { N = "32.00" }
      stock      = { N = "15" }
      dims_cm    = { S = "4x4x10" }
      weight_kg  = { N = "0.09" }
    }

    "ATN-BAR-001" = {
      product_id = { S = "ATN-BAR-001" }
      category   = { S = "barbe" }
      name       = { S = "Huile à Barbe Bois Sombre" }
      description = { S = "Huile de soin au toucher soyeux pour assouplir et discipliner la barbe." }
      price_eur  = { N = "28.00" }
      stock      = { N = "22" }
      dims_cm    = { S = "4x4x11" }
      weight_kg  = { N = "0.11" }
    }

    "ATN-BAR-002" = {
      product_id = { S = "ATN-BAR-002" }
      category   = { S = "barbe" }
      name       = { S = "Baume Structurant" }
      description = { S = "Baume nourrissant pour une barbe douce et maîtrisée." }
      price_eur  = { N = "26.00" }
      stock      = { N = "20" }
      dims_cm    = { S = "7x7x3" }
      weight_kg  = { N = "0.10" }
    }

    "ATN-BAR-003" = {
      product_id = { S = "ATN-BAR-003" }
      category   = { S = "barbe" }
      name       = { S = "Nettoyant Barbe Quotidien" }
      description = { S = "Nettoie délicatement la barbe et la peau en dessous." }
      price_eur  = { N = "19.00" }
      stock      = { N = "26" }
      dims_cm    = { S = "5x5x15" }
      weight_kg  = { N = "0.20" }
    }

    "ATN-COR-001" = {
      product_id = { S = "ATN-COR-001" }
      category   = { S = "corps" }
      name       = { S = "Gel Douche Cèdre & Sauge" }
      description = { S = "Nettoyant corps au parfum végétal et boisé, pour le rituel quotidien." }
      price_eur  = { N = "22.00" }
      stock      = { N = "28" }
      dims_cm    = { S = "6x6x19" }
      weight_kg  = { N = "0.30" }
    }

    "ATN-COR-002" = {
      product_id = { S = "ATN-COR-002" }
      category   = { S = "corps" }
      name       = { S = "Lait Corps Velours" }
      description = { S = "Soin hydratant à la texture légère et au fini confortable." }
      price_eur  = { N = "29.00" }
      stock      = { N = "17" }
      dims_cm    = { S = "6x5x17" }
      weight_kg  = { N = "0.25" }
    }

    "ATN-COR-003" = {
      product_id = { S = "ATN-COR-003" }
      category   = { S = "corps" }
      name       = { S = "Exfoliant Minéral" }
      description = { S = "Exfoliant doux à intégrer une à deux fois par semaine." }
      price_eur  = { N = "25.00" }
      stock      = { N = "14" }
      dims_cm    = { S = "7x7x6" }
      weight_kg  = { N = "0.20" }
    }

    "ATN-PAR-001" = {
      product_id = { S = "ATN-PAR-001" }
      category   = { S = "parfums" }
      name       = { S = "Eau de Parfum Sillage 01" }
      description = { S = "Accord boisé et ambré, profond et contemporain. Format 50 ml." }
      price_eur  = { N = "89.00" }
      stock      = { N = "12" }
      dims_cm    = { S = "7x7x13" }
      weight_kg  = { N = "0.32" }
    }

    "ATN-PAR-002" = {
      product_id = { S = "ATN-PAR-002" }
      category   = { S = "parfums" }
      name       = { S = "Eau de Parfum Minuit" }
      description = { S = "Accord aromatique et épicé, élégant du soir au quotidien. Format 50 ml." }
      price_eur  = { N = "95.00" }
      stock      = { N = "9" }
      dims_cm    = { S = "7x7x13" }
      weight_kg  = { N = "0.32" }
    }
  }
}

# Enregistre les produits dans DynamoDB via Terraform.
resource "aws_dynamodb_table_item" "seed_products" {
  for_each   = local.initial_products
  table_name = aws_dynamodb_table.products.name
  hash_key   = aws_dynamodb_table.products.hash_key
  item       = jsonencode(each.value)
}

# 3. Table des commandes et du suivi d'audit
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

  tags = {
    Project = var.project_name
    Purpose = "Commandes"
  }
}

# 4. Bucket S3 pour les factures PDF et rapports d'audit
resource "aws_s3_bucket" "invoices" {
  bucket        = "${var.project_name}-invoices-${var.account_id}"
  force_destroy = true

  tags = {
    Project = var.project_name
    Purpose = "Factures et rapports"
  }
}
