#!/usr/bin/env bash
# ==============================================================================
# Script de Setup initial - CloudShop AWS (Linux/macOS)
# ==============================================================================
set -e

echo "=========================================================="
echo " CloudShop FISA 2026 - Setup Initial Architecture        "
echo "=========================================================="

echo -e "\n[1/5] Vérification des prérequis..."
command -v terraform >/dev/null 2>&1 || { echo "Erreur: Terraform n'est pas installé." >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "Erreur: AWS CLI n'est pas installé." >&2; exit 1; }

echo -e "\n[2/5] Initialisation du projet (terraform init)..."
terraform init

echo -e "\n[3/5] Validation du code d'infrastructure (terraform validate)..."
terraform validate

echo -e "\n[4/5] Déploiement des ressources AWS (terraform apply)..."
terraform apply -auto-approve

echo -e "\n[5/5] Création du compte administrateur..."
USER_POOL_ID=$(terraform output -raw user_pool_id 2>/dev/null || echo "")

if [ -n "$USER_POOL_ID" ]; then
  ADMIN_EMAIL="admin@neolia.com"

  if command -v openssl &> /dev/null; then
    RAW_PASS=$(openssl rand -base64 12)
  else
    RAW_PASS=$(date +%s | sha256sum | base64 | head -c 12)
  fi
  ADMIN_PASSWORD="N3o!${RAW_PASS:0:8}"

  aws cognito-idp admin-create-user \
    --user-pool-id "$USER_POOL_ID" \
    --username "$ADMIN_EMAIL" \
    --user-attributes Name=email,Value="$ADMIN_EMAIL" Name=email_verified,Value=true Name=given_name,Value="Admin" Name=family_name,Value="Neolia" \
    --temporary-password "$ADMIN_PASSWORD" \
    --message-action SUPPRESS 2>/dev/null || true

  aws cognito-idp admin-set-user-password \
    --user-pool-id "$USER_POOL_ID" \
    --username "$ADMIN_EMAIL" \
    --password "$ADMIN_PASSWORD" \
    --permanent 2>/dev/null || true

  aws cognito-idp admin-add-user-to-group \
    --user-pool-id "$USER_POOL_ID" \
    --username "$ADMIN_EMAIL" \
    --group-name Admins 2>/dev/null || true
fi

echo -e "\n=========================================================="
echo "         SETUP INITIAL TERMINÉ AVEC SUCCÈS !              "
echo "=========================================================="

URL=$(terraform output -raw website_url 2>/dev/null || echo "")
if [ -n "$URL" ]; then
  echo -e "\nURL de la boutique : $URL"
fi

if [ -n "$USER_POOL_ID" ] && [ -n "$ADMIN_PASSWORD" ]; then
  echo -e "\nIdentifiants Administrateur :"
  echo "  E-mail      : $ADMIN_EMAIL"
  echo "  Mot de passe : $ADMIN_PASSWORD"
fi
