#!/bin/bash
# ==============================================================================
# Script de synchronisation S3 Remote State et relance CloudShop (Linux/macOS/Bash)
# ==============================================================================
set -e

echo "=========================================================="
echo " CloudShop FISA 2026 - Sync S3 Remote State & Relance    "
echo "=========================================================="

echo -e "\n[1/4] Récupération du code et de l'architecture (git pull)..."
git pull origin main || true

echo -e "\n[2/4] Synchronisation avec l'état distant S3 (terraform init -reconfigure)..."
terraform init -reconfigure

echo -e "\n[3/4] Validation du code d'infrastructure..."
terraform validate

echo -e "\n[4/4] Application du déploiement synchronisé (terraform apply)..."
terraform apply -auto-approve

echo -e "\n=========================================================="
echo "     DÉPLOIEMENT SYNCHRONISÉ TERMINÉ AVEC SUCCÈS !       "
echo "=========================================================="
URL=$(terraform output -raw website_url 2>/dev/null || echo "")
if [ -n "$URL" ]; then
  echo -e "\n🌐 URL du site : $URL"
fi
