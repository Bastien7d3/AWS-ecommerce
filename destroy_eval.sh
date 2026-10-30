#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE SUPPRESSION PROPRE POUR ÉVALUATION (Linux / macOS)
# Projet : NÉOLIA CloudShop - IMT FISA 2026
# ==============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${RED}================================================================${NC}"
echo -e "${RED}   NÉOLIA CloudShop - Nettoyage Complet de l'Infrastructure      ${NC}"
echo -e "${RED}================================================================${NC}"

read -p "Êtes-vous sûr de vouloir détruire toutes les ressources AWS du projet ? [o/N] : " CONFIRM
if [[ ! "$CONFIRM" =~ ^[oOyY]$ ]]; then
    echo -e "${YELLOW}Destruction annulée.${NC}"
    exit 0
fi

echo -e "\n${YELLOW}[1/3] Vente et nettoyage préventif des buckets S3...${NC}"
BUCKET_NAME=$(terraform output -raw s3_invoices_bucket 2>/dev/null || echo "")
if [ -n "$BUCKET_NAME" ]; then
    echo -e "Vidage du bucket $BUCKET_NAME..."
    aws s3 rm "s3://$BUCKET_NAME" --recursive 2>/dev/null || true
fi

echo -e "\n${YELLOW}[2/3] Destruction des ressources Terraform (terraform destroy)...${NC}"
terraform destroy -auto-approve

echo -e "\n${YELLOW}[3/3] Restauration des fichiers de configuration...${NC}"
if [ -f "backend.tf.disabled" ]; then
    mv backend.tf.disabled backend.tf
    echo -e "  ✔ Fichier backend.tf restauré."
fi

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}      NETTOYAGE TERMINÉ : 0 RESSOURCE EN COURS D'EXPLOITATION    ${NC}"
echo -e "${GREEN}================================================================${NC}\n"
