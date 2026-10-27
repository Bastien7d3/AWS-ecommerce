<#
.SYNOPSIS
    Script de synchronisation et relance automatique du projet CloudShop AWS.
.DESCRIPTION
    1. Récupère la dernière version du code (git pull).
    2. Rafraîchit les variables d'environnement (PATH Terraform / AWS CLI).
    3. Réinitialise Terraform avec les nouveaux modules (terraform init -upgrade).
    4. Valide la syntaxe (terraform validate).
    5. Applique les changements (terraform apply -auto-approve).
    6. Affiche l'URL publique et les identifiants clés du projet.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  CloudShop FISA 2026 - Synchronisation & Relance Propre  " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Mise à jour de l'environnement PATH
Write-Host "`n[1/5] Vérification de l'environnement..." -ForegroundColor Yellow
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Error "Terraform n'est pas trouvé dans le PATH. Veuillez vérifier son installation."
    exit 1
}

# 2. Git Pull
Write-Host "`n[2/5] Récupération des dernières modifications (git pull)..." -ForegroundColor Yellow
try {
    $pullOutput = git pull origin main
    Write-Host $pullOutput -ForegroundColor Gray
} catch {
    Write-Warning "Attention lors du git pull : $_"
    Write-Host "Poursuite du déploiement avec les fichiers locaux..." -ForegroundColor Gray
}

# 3. Terraform Init (avec -upgrade pour charger tous les nouveaux modules)
Write-Host "`n[3/5] Initialisation des modules et providers Terraform..." -ForegroundColor Yellow
terraform init -upgrade

# 4. Terraform Validate
Write-Host "`n[4/5] Validation du code d'infrastructure..." -ForegroundColor Yellow
$validation = terraform validate
if ($LASTEXITCODE -ne 0) {
    Write-Error "Échec de validation Terraform. Corrigez les erreurs avant d'appliquer."
    exit 1
}
Write-Host "Configuration Terraform valide !" -ForegroundColor Green

# 5. Terraform Apply
Write-Host "`n[5/5] Application du déploiement sur AWS (terraform apply)..." -ForegroundColor Yellow
terraform apply -auto-approve

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host "           DÉPLOIEMENT TERMINÉ AVEC SUCCÈS !             " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    
    $websiteUrl = terraform output -raw website_url 2>$null
    if ($websiteUrl) {
        Write-Host "`n🌐 URL du site : " -NoNewline
        Write-Host $websiteUrl -ForegroundColor Cyan
    }
} else {
    Write-Error "Erreur lors de l'application Terraform."
    exit 1
}
