<#
.SYNOPSIS
    Script de déploiement automatisé pour évaluation (Windows PowerShell).
.DESCRIPTION
    Projet : NÉOLIA CloudShop - IMT FISA 2027
    Auteurs : Bastien BRUNEL, William PEREIRA, Lucas DEBRUYNE

    1. Vérifie les prérequis (Terraform, AWS CLI, Session AWS).
    2. Isole le stockage Terraform en local pour éviter tout conflit de droits.
    3. Déploie l'architecture complète (terraform apply).
    4. Configure le compte administrateur admin@neolia.com dans Amazon Cognito.
    5. Affiche l'URL publique et le guide d'évaluation pas à pas.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   NÉOLIA CloudShop - Déploiement Évaluation AWS (FISA 2027)     " -ForegroundColor Cyan
Write-Host "   Auteurs : Bastien BRUNEL, William PEREIRA, Lucas DEBRUYNE    " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Vérification des prérequis logiciels
Write-Host "`n[1/6] Vérification des prérequis logiciels..." -ForegroundColor Yellow

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Error "Terraform est introuvable dans le PATH. Veuillez l'installer avant de lancer l'évaluation."
    exit 1
}

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Error "L'outil AWS CLI (aws) est introuvable dans le PATH."
    exit 1
}

$tfVer = (terraform version | Select-Object -First 1)
$awsVer = (aws --version 2>&1 | Select-Object -First 1)
Write-Host "  ✔ Terraform : $tfVer" -ForegroundColor Green
Write-Host "  ✔ AWS CLI   : $awsVer" -ForegroundColor Green

# 2. Vérification de l'authentification AWS
Write-Host "`n[2/6] Contrôle de la session et des accès AWS..." -ForegroundColor Yellow
try {
    $identityJson = aws sts get-caller-identity --output json 2>$null
    if (-not $identityJson) { throw "Session invalide" }
    $identity = $identityJson | ConvertFrom-Json
} catch {
    Write-Host "`nErreur : Impossible de contacter AWS avec vos identifiants actuels." -ForegroundColor Red
    Write-Host "Veuillez configurer vos accès AWS avant de lancer le script :"
    Write-Host "  - Soit via : aws configure" -ForegroundColor Cyan
    Write-Host "  - Soit en définissant les variables d'environnement `$env:AWS_ACCESS_KEY_ID et `$env:AWS_SECRET_ACCESS_KEY" -ForegroundColor Cyan
    exit 1
}

$accountId = $identity.Account
$userArn = $identity.Arn
$awsRegion = (aws configure get region 2>$null)
if (-not $awsRegion) { $awsRegion = "eu-west-3" }

Write-Host "  ✔ Compte AWS cible : $accountId" -ForegroundColor Green
Write-Host "  ✔ Identité Active  : $userArn" -ForegroundColor Green
Write-Host "  ✔ Région cible     : $awsRegion" -ForegroundColor Green

# 3. Isolation du backend Terraform pour l'évaluateur
Write-Host "`n[3/6] Configuration du stockage d'état Terraform (Mode Autonome)..." -ForegroundColor Yellow
if (Test-Path "backend.tf") {
    Rename-Item -Path "backend.tf" -NewName "backend.tf.disabled" -Force
    Write-Host "  ✔ Backend distant S3 basculé en backend local pour isoler votre déploiement." -ForegroundColor Green
} elseif (Test-Path "backend.tf.disabled") {
    Write-Host "  ✔ Backend local autonome déjà prêt." -ForegroundColor Green
}

# 4. Option notification e-mail
$notificationVar = @()
Write-Host "`n[4/6] Option Notifications E-mail (SNS)" -ForegroundColor Yellow
$profEmail = Read-Host "Entrez votre e-mail pour recevoir les notifications réelles (ou appuyez sur [Entrée] pour ignorer)"

if ($profEmail -and $profEmail.Trim() -ne "") {
    Write-Host "  ✔ Notifications activées pour : $profEmail" -ForegroundColor Green
    $notificationVar = @("-var", "notification_email=$profEmail")
} else {
    Write-Host "  ✔ Aucune adresse renseignée, notifications SNS externes ignorées." -ForegroundColor Gray
}

# 5. Déploiement Terraform
Write-Host "`n[5/6] Déploiement de l'infrastructure Cloud AWS..." -ForegroundColor Yellow
terraform init -reconfigure
if ($LASTEXITCODE -ne 0) {
    Write-Error "Échec de l'initialisation Terraform."
    exit 1
}

Write-Host "Application du plan Terraform (création des briques IaaS, Serverless & Spot)..."
terraform apply -auto-approve @notificationVar
if ($LASTEXITCODE -ne 0) {
    Write-Error "Erreur lors du déploiement Terraform."
    exit 1
}

# 6. Configuration de l'administrateur Cognito
Write-Host "`n[6/6] Configuration du compte Administrateur NÉOLIA..." -ForegroundColor Yellow
$userPoolId = terraform output -raw user_pool_id 2>$null
$adminEmail = "admin@neolia.com"
$adminPassword = "Neolia2026!Admin"

if ($userPoolId) {
    Write-Host "Création du compte administrateur dans Amazon Cognito ($adminEmail)..."

    # Création du compte si inexistant
    aws cognito-idp admin-create-user `
      --user-pool-id "$userPoolId" `
      --username "$adminEmail" `
      --user-attributes Name=email,Value="$adminEmail" Name=email_verified,Value=true Name=given_name,Value="Admin" Name=family_name,Value="Neolia" `
      --temporary-password "$adminPassword" `
      --message-action SUPPRESS 2>$null

    # Définition du mot de passe permanent
    aws cognito-idp admin-set-user-password `
      --user-pool-id "$userPoolId" `
      --username "$adminEmail" `
      --password "$adminPassword" `
      --permanent 2>$null

    # Association au groupe admin
    aws cognito-idp admin-add-user-to-group `
      --user-pool-id "$userPoolId" `
      --username "$adminEmail" `
      --group-name "admin" 2>$null

    Write-Host "  ✔ Compte Administrateur Cognito configuré et prêt." -ForegroundColor Green
} else {
    Write-Warning "Impossible de lire user_pool_id depuis les outputs Terraform."
}

# Récupération des URLs
$websiteUrl = terraform output -raw website_url 2>$null
$albDns = terraform output -raw alb_dns_name 2>$null

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "       DÉPLOIEMENT RÉUSSI ! L'ARCHITECTURE EST EN LIGNE         " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

Write-Host "`nACCÈS À LA BOUTIQUE :" -ForegroundColor Cyan
if ($websiteUrl) {
    Write-Host "  URL Public CloudFront (HTTPS) : " -NoNewline
    Write-Host $websiteUrl -ForegroundColor Green
}
if ($albDns) {
    Write-Host "  URL Direct ALB (HTTP)          : http://$albDns" -ForegroundColor Gray
}

Write-Host "`nIDENTIFIANTS ADMINISTRATEUR NÉOLIA :" -ForegroundColor Cyan
Write-Host "  URL d'administration : $websiteUrl/admin" -ForegroundColor Green
Write-Host "  E-mail               : $adminEmail" -ForegroundColor Green
Write-Host "  Mot de passe         : $adminPassword" -ForegroundColor Yellow

Write-Host "`nSCÉNARIO RAPIDE D'ÉVALUATION EN 4 ÉTAPES (3 min) :" -ForegroundColor Cyan
Write-Host "  1. Navigation & Commande : Ouvrez la boutique, ajoutez un cosmétique (ex: Gel Nettoyant) et validez la commande."
Write-Host "  2. Serverless & Stock   : La Lambda décrémente instantanément le stock dans DynamoDB et publie dans SQS + SNS."
Write-Host "  3. Espace Admin & Spot  : Allez sur /admin, observez la commande en attente dans la file SQS, puis cliquez sur 'Lancer le Worker EC2 Spot'."
Write-Host "  4. Facture & Clôture    : Le worker Spot démarre, compile la facture PDF dans Amazon S3, et s'auto-détruit (Scale-to-Zero)."

Write-Host "`nPOUR TOUT NETTOYER APRÈS L'ÉVALUATION (0€ de frais résiduels) :" -ForegroundColor Yellow
Write-Host "  Exécutez simplement : .\destroy_eval.ps1`n" -ForegroundColor Cyan
