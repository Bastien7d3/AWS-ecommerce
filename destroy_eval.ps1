<#
.SYNOPSIS
    Script de nettoyage complet pour évaluation (Windows PowerShell).
.DESCRIPTION
    Détruit l'intégralité des ressources AWS créées pour le projet.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Red
Write-Host "   NÉOLIA CloudShop - Nettoyage Complet de l'Infrastructure      " -ForegroundColor Red
Write-Host "================================================================" -ForegroundColor Red

$confirm = Read-Host "Êtes-vous sûr de vouloir détruire toutes les ressources AWS du projet ? [o/N]"
if ($confirm -notmatch '^[oOyY]$') {
    Write-Host "Destruction annulée." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n[1/3] Vidage préventif du bucket S3 des factures..." -ForegroundColor Yellow
try {
    $bucketName = terraform output -raw s3_invoices_bucket 2>$null
    if ($bucketName) {
        Write-Host "Vidage du bucket $bucketName..."
        aws s3 rm "s3://$bucketName" --recursive 2>$null
    }
} catch {
    Write-Warning "Impossible de vider le bucket automatiquement."
}

Write-Host "`n[2/3] Destruction des ressources Terraform (terraform destroy)..." -ForegroundColor Yellow
terraform destroy -auto-approve
if ($LASTEXITCODE -ne 0) {
    Write-Error "Erreur lors de la destruction Terraform."
    exit 1
}

Write-Host "`n[3/3] Restauration des fichiers de configuration..." -ForegroundColor Yellow
if (Test-Path "backend.tf.disabled") {
    Rename-Item -Path "backend.tf.disabled" -NewName "backend.tf" -Force
    Write-Host "  ✔ Fichier backend.tf restauré." -ForegroundColor Green
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "      NETTOYAGE TERMINÉ : 0 RESSOURCE EN COURS D'EXPLOITATION    " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
