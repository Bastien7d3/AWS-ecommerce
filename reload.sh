#!/bin/bash
# ==============================================================================
# Script de synchronisation et relance automatique du projet CloudShop AWS (Linux/macOS/Git Bash)
# ==============================================================================
set -e

echo "=========================================================="
echo "  CloudShop FISA 2026 - Synchronisation & Relance Propre  "
echo "=========================================================="

echo -e "\n[1/4] Récupération des dernières modifications (git pull)..."
git pull origin main || true

echo -e "\n[2/4] Initialisation des modules et providers Terraform..."
terraform init -upgrade

echo -e "\n[3/4] Validation du code d'infrastructure..."
terraform validate

echo -e "\n[4/4] Application du déploiement sur AWS (terraform apply)..."
terraform apply -auto-approve

echo -e "\n=========================================================="
echo "           DÉPLOIEMENT TERMINÉ AVEC SUCCÈS !             "
echo "=========================================================="
URL=$(terraform output -raw website_url 2>/dev/null || echo "")
if [ -n "$URL" ]; then
  echo -e "\n🌐 URL du site : $URL"
fi
