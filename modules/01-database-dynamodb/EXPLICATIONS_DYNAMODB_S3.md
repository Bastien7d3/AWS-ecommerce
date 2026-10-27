# Module 01 : Base de Données DynamoDB & Stockage S3

Ce module gère la persistance des données transactionnelles et le stockage des fichiers volumineux ([`main.tf`](./main.tf)).

---

## 1. Composants Déployés

1. **Table DynamoDB `products` (Catalogue Produits) :**
   * Clé de partition : `product_id` (ex : `ATN-VIS-001`).
   * Contient les références du catalogue pré-insérées automatiquement par Terraform, avec nom, catégorie, description, prix HT (`price_eur`), stock disponible (`stock`), dimensions en cm (`dims_cm`) et poids en kg (`weight_kg`).
   * Ces dimensions et poids alimentent directement l'algorithme de calcul de colisage du Worker Spot.
2. **Table DynamoDB `orders` (Commandes & Audit) :**
   * Clé de partition : `order_id` (ex : `CMD-2026-XXXXXX`).
   * Enregistre le cycle de vie complet de chaque commande : statut évolutif (`PENDING` → `SHIPPED`), coordonnées client, référence du carton retenu (`Colis S/M/L/XL`), taux de remplissage, numéro de suivi transporteur et clé S3 de la facture PDF.
3. **Bucket Amazon S3 `invoices` (Archivage des Factures PDF) :**
   * Stocke les factures PDF officielles générées par le Worker Spot (`invoices/facture_CMD-....pdf`).
   * Configuré avec `force_destroy = true` pour permettre une destruction intégrale et propre lors d'un `terraform destroy` sans laisser de stockage orphelin.

---

## 2. Flux de Données & Connexions

```
[Front-End EC2] ──(Lecture Catalogue)──► Table DynamoDB 'products'
       │
   (Commande)
       ▼
 [Lambda Order] ──(Décrémente Stock)──► Table DynamoDB 'products'
       │        ──(Insère PENDING)────► Table DynamoDB 'orders'
       ▼
 [SQS Queue]
       ▼
 [Worker Spot]  ──(Upload PDF)────────► Bucket Amazon S3 'invoices'
                ──(Mise à jour SHIPPED)► Table DynamoDB 'orders'
```

---

## 3. Justification FinOps

* **Mode Provisionné vs On-Demand :** Les tables sont configurées en mode `PROVISIONED` avec **5 RCU** (Read Capacity Units) et **5 WCU** (Write Capacity Units).
* **Couverture Free Tier :** L'offre permanente *Always Free* d'AWS alloue **25 RCU et 25 WCU** au total sur le compte. Nos deux tables n'en consomment que 10 au total (5 + 5), garantissant une facturation de **0,00 €**.
* **Stockage S3 :** Les factures PDF (environ 2,5 Ko par document) représentent un volume négligeable, largement inclus dans les 5 Go du Free Tier mensuel.
