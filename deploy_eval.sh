#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE DÉPLOIEMENT AUTOMATISÉ POUR ÉVALUATION (Linux / macOS)
# Projet : NÉOLIA CloudShop - IMT FISA 2027
# Binôme / Équipe : Bastien BRUNEL, William PEREIRA, Lucas DEBRUYNE
# ==============================================================================
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}   NÉOLIA CloudShop - Déploiement Évaluation AWS (FISA 2027)     ${NC}"
echo -e "${CYAN}   Auteurs : Bastien BRUNEL, William PEREIRA, Lucas DEBRUYNE    ${NC}"
echo -e "${CYAN}================================================================${NC}"

# 1. Vérification des outils nécessaires
echo -e "\n${YELLOW}[1/6] Vérification des prérequis logiciels...${NC}"
command -v terraform >/dev/null 2>&1 || { echo -e "${RED}Erreur : Terraform est introuvable dans le PATH.${NC}" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}Erreur : AWS CLI est introuvable dans le PATH.${NC}" >&2; exit 1; }

TERRAFORM_VERSION=$(terraform version | head -n 1)
echo -e "  ✔ Terraform détecté : $TERRAFORM_VERSION"
AWS_VERSION=$(aws --version | head -n 1)
echo -e "  ✔ AWS CLI détecté   : $AWS_VERSION"

# 2. Vérification de l'authentification AWS
echo -e "\n${YELLOW}[2/6] Contrôle de la session et des accès AWS...${NC}"
CALLER_IDENTITY=$(aws sts get-caller-identity 2>/dev/null || echo "")

if [ -z "$CALLER_IDENTITY" ]; then
    echo -e "${RED}Erreur : Impossible de contacter AWS avec vos identifiants actuels.${NC}"
    echo -e "Veuillez configurer vos accès AWS avant de lancer le script :"
    echo -e "  - Soit via : ${CYAN}aws configure${NC}"
    echo -e "  - Soit en exportant vos clés : ${CYAN}export AWS_ACCESS_KEY_ID=... && export AWS_SECRET_ACCESS_KEY=...${NC}"
    exit 1
fi

ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
USER_ARN=$(echo "$CALLER_IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
AWS_REGION=$(aws configure get region 2>/dev/null || echo "eu-west-3")
if [ -z "$AWS_REGION" ]; then AWS_REGION="eu-west-3"; fi

echo -e "  ✔ Compte AWS cible : ${GREEN}$ACCOUNT_ID${NC}"
echo -e "  ✔ Identité Active  : ${GREEN}$USER_ARN${NC}"
echo -e "  ✔ Région cible     : ${GREEN}$AWS_REGION${NC}"

# 3. Isolation du backend Terraform pour l'évaluateur
echo -e "\n${YELLOW}[3/6] Configuration du stockage d'état Terraform (Mode Autonome)...${NC}"
# Si backend.tf existe (pointant sur le S3 partagé étudiant), on le désactive pour l'évaluateur
if [ -f "backend.tf" ]; then
    mv backend.tf backend.tf.disabled
    echo -e "  ✔ Backend distant S3 basculé en backend local pour isoler votre déploiement."
elif [ -f "backend.tf.disabled" ]; then
    echo -e "  ✔ Backend local autonome déjà prêt."
fi

# 4. Option notification e-mail
NOTIFICATION_ARG=""
echo -e "\n${YELLOW}[4/6] Option Notifications E-mail (SNS)${NC}"
echo -e "Souhaitez-vous recevoir les e-mails de notification (confirmation commande + expédition) ?"
read -p "Entrez votre e-mail (ou appuyez sur [Entrée] pour ignorer) : " PROF_EMAIL

if [ -n "$PROF_EMAIL" ]; then
    echo -e "  ✔ Notifications activées pour : ${GREEN}$PROF_EMAIL${NC}"
    NOTIFICATION_ARG="-var=notification_email=$PROF_EMAIL"
else
    echo -e "  ✔ Aucune adresse renseignée, notifications SNS externes ignorées."
fi

# 5. Initialisation & Déploiement Terraform
echo -e "\n${YELLOW}[5/6] Déploiement de l'infrastructure Cloud AWS...${NC}"
terraform init -reconfigure
echo -e "Application du plan Terraform (création des briques IaaS, Serverless & Spot)..."
terraform apply -auto-approve $NOTIFICATION_ARG

# 6. Initialisation de l'administrateur Cognito
echo -e "\n${YELLOW}[6/6] Configuration du compte Administrateur NÉOLIA...${NC}"
USER_POOL_ID=$(terraform output -raw user_pool_id 2>/dev/null || echo "")

ADMIN_EMAIL="admin@neolia.com"
ADMIN_PASSWORD="Neolia2026!Admin"

if [ -n "$USER_POOL_ID" ]; then
    echo -e "Création du compte administrateur dans Amazon Cognito ($ADMIN_EMAIL)..."

    # Création du compte si inexistant
    aws cognito-idp admin-create-user \
      --user-pool-id "$USER_POOL_ID" \
      --username "$ADMIN_EMAIL" \
      --user-attributes Name=email,Value="$ADMIN_EMAIL" Name=email_verified,Value=true Name=given_name,Value="Admin" Name=family_name,Value="Neolia" \
      --temporary-password "$ADMIN_PASSWORD" \
      --message-action SUPPRESS 2>/dev/null || true

    # Définition du mot de passe permanent
    aws cognito-idp admin-set-user-password \
      --user-pool-id "$USER_POOL_ID" \
      --username "$ADMIN_EMAIL" \
      --password "$ADMIN_PASSWORD" \
      --permanent 2>/dev/null || true

    # Association au groupe admin
    aws cognito-idp admin-add-user-to-group \
      --user-pool-id "$USER_POOL_ID" \
      --username "$ADMIN_EMAIL" \
      --group-name "admin" 2>/dev/null || true

    echo -e "  ✔ Compte Administrateur Cognito configuré et prêt."
else
    echo -e "${YELLOW}  Attention : Impossible de récupérer le User Pool ID Cognito.${NC}"
fi

# Récupération des URLs
WEBSITE_URL=$(terraform output -raw website_url 2>/dev/null || echo "")
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}       DÉPLOIEMENT RÉUSSI ! L'ARCHITECTURE EST EN LIGNE         ${NC}"
echo -e "${GREEN}================================================================${NC}"

echo -e "\n${CYAN}ACCÈS À LA BOUTIQUE :${NC}"
if [ -n "$WEBSITE_URL" ]; then
    echo -e "  URL Public CloudFront (HTTPS) : ${GREEN}$WEBSITE_URL${NC}"
fi
if [ -n "$ALB_DNS" ]; then
    echo -e "  URL Direct ALB (HTTP)          : http://$ALB_DNS"
fi

echo -e "\n${CYAN}IDENTIFIANTS ADMINISTRATEUR NÉOLIA :${NC}"
echo -e "  URL d'administration : ${GREEN}$WEBSITE_URL/admin${NC}"
echo -e "  E-mail               : ${GREEN}$ADMIN_EMAIL${NC}"
echo -e "  Mot de passe         : ${GREEN}$ADMIN_PASSWORD${NC}"

echo -e "\n${YELLOW}POUR TOUT NETTOYER APRÈS L'ÉVALUATION (0€ de frais résiduels) :${NC}"
echo -e "  Exécutez simplement : ${CYAN}./destroy_eval.sh${NC}\n"
