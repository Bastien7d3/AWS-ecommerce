# PoC Terraform : Worker Batch EC2 Spot — Facture PDF, Colisage & Suivi SNS

Ce dossier contient le **Proof of Concept (PoC) fonctionnel** testé en conditions réelles sur le compte AWS `689505268069` (`eu-west-3`).

## Fichiers présents dans ce dossier

1. **`main.tf`** : Infrastructure-as-Code Terraform complète (14 ressources AWS) :
   * Bucket S3 (`poc-cloudshop-invoices-...`)
   * Table DynamoDB (`poc-cloudshop-orders`) en mode *Provisioned* (5 RCU / 5 WCU = *Always Free*)
   * File d'attente SQS (`poc-orders-batch-queue`)
   * Topic SNS (`poc-order-shipped-topic`)
   * 2 Alarmes CloudWatch (`CloudShop-SQS-Batch-Start-Threshold` et `CloudShop-SQS-Batch-Split-Surge-Threshold`) pilotées par les variables administrateur `admin_spot_trigger_threshold` et `admin_spot_split_threshold`
   * Rôle IAM moindre privilège + Security Group (aucun port entrant ouvert)
   * Instance **EC2 Spot (`t3.micro`)** avec disque 8 Go `gp3`
2. **`worker.py.tftpl`** : Script Python exécuté automatiquement par l'instance EC2 Spot au démarrage :
   * Récupère la commande depuis SQS
   * Calcule le volume (+15 % de calage) et le poids total pour sélectionner le carton transporteur optimal parmi **Colis S, Colis M, Colis L, Colis XL**
   * Génère la facture PDF officielle avec `fpdf2` et l'envoie sur S3
   * Met à jour le statut de la commande dans DynamoDB (`PENDING` $\rightarrow$ `PACKAGED` $\rightarrow$ `SHIPPED`)
   * Publie le numéro de suivi transporteur (`TRK-EUW3-...`) et le lien pré-signé du PDF sur **Amazon SNS**
3. **`facture_CMD-2026-001.pdf`** : Exemple réel de facture PDF générée sur AWS par l'instance EC2 Spot `i-07945481eb776828e`.
4. **`report_CMD-2026-001.json`** : Trace d'audit JSON générée par l'instance Spot.

---

## Comment relancer le PoC en direct devant le groupe ou le professeur

```powershell
# 1. Se placer dans le dossier
cd 04_POC_TERRAFORM_EC2_SPOT_PDF

# 2. Initialiser et déployer sur AWS (~25 secondes)
terraform init
terraform apply -auto-approve

# 3. Attendre ~45 secondes que l'EC2 Spot génère le PDF, puis télécharger la facture depuis S3 :
$bucket = terraform output -raw s3_invoices_bucket
aws s3 cp "s3://$bucket/invoices/facture_CMD-2026-001.pdf" ./facture_test_live.pdf

# 4. Vérifier le statut SHIPPED et le numéro de suivi dans DynamoDB :
aws dynamodb get-item --table-name poc-cloudshop-orders --key '{"order_id":{"S":"CMD-2026-001"}}'

# 5. Détruire intégralement l'infrastructure pour revenir à 0,00 € :
terraform destroy -auto-approve
```
