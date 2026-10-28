<#
.SYNOPSIS
    Script de Setup initial du projet CloudShop AWS.
.DESCRIPTION
    1. Vérifie la présence des prérequis (Terraform et AWS CLI).
    2. Initialise le projet Terraform et le backend S3 (terraform init).
    3. Valide le code Terraform (terraform validate).
    4. Déploie l'ensemble de l'architecture AWS (terraform apply).
    5. Crée automatiquement le compte administrateur admin@neolia.com dans Cognito.
    6. Affiche l'URL publique de la boutique et les identifiants d'accès.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " CloudShop FISA 2026 - Setup Initial Architecture        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Vérification de l'environnement
Write-Host "`n[1/5] Vérification des prérequis..." -ForegroundColor Yellow
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Error "Terraform est introuvable dans le PATH. Veuillez l'installer avant de lancer le setup."
    exit 1
}

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Error "L'outil AWS CLI (aws) est introuvable dans le PATH. Il est requis pour le setup."
    exit 1
}

# 2. Initialisation Terraform
Write-Host "`n[2/5] Initialisation du projet et du backend (terraform init)..." -ForegroundColor Yellow
terraform init

if ($LASTEXITCODE -ne 0) {
    Write-Error "Échec de l'initialisation Terraform."
    exit 1
}

# 3. Validation de la configuration
Write-Host "`n[3/5] Validation du code d'infrastructure (terraform validate)..." -ForegroundColor Yellow
$null = terraform validate
if ($LASTEXITCODE -ne 0) {
    Write-Error "Code Terraform invalide. Corrigez les erreurs avant de poursuivre."
    exit 1
}
Write-Host "Configuration Terraform valide !" -ForegroundColor Green

# 4. Déploiement Terraform
Write-Host "`n[4/5] Déploiement des ressources AWS (terraform apply)..." -ForegroundColor Yellow
terraform apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Error "Erreur lors du déploiement Terraform."
    exit 1
}

# 5. Création de l'Administrateur Cognito
Write-Host "`n[5/5] Création du compte administrateur par défaut..." -ForegroundColor Yellow
$userPoolId = terraform output -raw user_pool_id 2>$null

if ($userPoolId) {
    $adminEmail = "admin@neolia.com"
    $Assembly = Add-Type -AssemblyName System.Web
    $RandomStr = [System.Web.Security.Membership]::GeneratePassword(8, 2)
    $adminPassword = "N3o!$RandomStr"

    try {
        aws cognito-idp admin-create-user `
          --user-pool-id "$userPoolId" `
          --username "$adminEmail" `
          --user-attributes Name=email,Value="$adminEmail" Name=email_verified,Value=true Name=given_name,Value="Admin" Name=family_name,Value="Neolia" `
          --temporary-password "$adminPassword" `
          --message-action SUPPRESS 2>$null

        aws cognito-idp admin-set-user-password `
          --user-pool-id "$userPoolId" `
          --username "$adminEmail" `
          --password "$adminPassword" `
          --permanent

        aws cognito-idp admin-add-user-to-group `
          --user-pool-id "$userPoolId" `
          --username "$adminEmail" `
          --group-name Admins

        $adminCreated = $true
    } catch {
        Write-Warning "Le compte administrateur existe déjà ou l'appel AWS CLI a échoué."
        $adminCreated = $false
    }
} else {
    Write-Warning "Impossible de lire user_pool_id depuis les outputs Terraform."
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "         SETUP INITIAL TERMINÉ AVEC SUCCÈS !              " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

$websiteUrl = terraform output -raw website_url 2>$null
if ($websiteUrl) {
    Write-Host "`nURL de la boutique : " -NoNewline
    Write-Host $websiteUrl -ForegroundColor Cyan
}

if ($adminCreated) {
    Write-Host "`nIdentifiants Administrateur :" -ForegroundColor Yellow
    Write-Host "  E-mail      : $adminEmail"
    Write-Host "  Mot de passe : $adminPassword" -ForegroundColor Cyan
}
