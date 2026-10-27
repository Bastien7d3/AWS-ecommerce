# Module 01 : Base de Données DynamoDB & Stockage S3

Ce dossier contient l'infrastructure de persistance des données de la boutique ([`main.tf`](./main.tf)).

---

## 1. Ce que déploie ce module

1. **Table DynamoDB `products` (Catalogue de la boutique) :**
   * Clé primaire (Partition Key) : `product_id` (ex : `"PROD-01"`).
   * Contient les articles pré-insérés automatiquement par Terraform (`aws_dynamodb_table_item.seed_products`) avec leur nom, prix HT (`price_eur`), stock disponible (`stock`), dimensions en cm (`dims_cm`) et poids en kg (`weight_kg`).
2. **Table DynamoDB `orders` (Commandes & Journal d'Audit) :**
   * Clé primaire (Partition Key) : `order_id` (ex : `"CMD-2026-..."`).
   * Enregistre chaque commande passée par un client avec son statut évolutif (`PENDING` $\rightarrow$ `PACKAGED` $\rightarrow$ `SHIPPED`), le numéro de suivi transporteur, la taille du carton retenu et le chemin de la facture PDF.
3. **Bucket Amazon S3 `invoices` (Stockage des Factures PDF & Rapports) :**
   * Stocke les factures PDF générées par l'instance EC2 Spot (`invoices/facture_CMD-....pdf`) ainsi que les rapports JSON d'audit (`reports/report_CMD-....json`).

---

## 2. Pourquoi cette configuration est 100 % Gratuite (AWS Free Tier)

* **Piège évité sur DynamoDB :** Par défaut, beaucoup de tutoriels utilisent `billing_mode = "PAY_PER_REQUEST"` (On-Demand), qui est facturé dès la première requête hors crédits.
* **Notre choix FinOps :** Nous utilisons `billing_mode = "PROVISIONED"` avec `read_capacity = 5` et `write_capacity = 5`. L'offre **Always Free** d'AWS inclut gratuitement **25 RCU et 25 WCU** cumulés sur le compte (nos 2 tables consomment $5 + 5 = 10\text{ unités} \le 25$, soit **0,00 €**).
* **Stockage S3 :** L'option `force_destroy = true` permet à `terraform destroy` de vider et supprimer automatiquement le compartiment S3 même s'il contient des factures PDF, évitant tout stockage résiduel.

---

## 3. Comment ce module est connecté aux autres

* **Vers `03-serverless-lambda` :** La fonction Lambda reçoit les noms et ARN des tables `products` et `orders` pour décrémenter le stock et enregistrer la nouvelle commande au statut `PENDING`.
* **Vers `04-frontend-ec2` :** Le serveur web Front-End lit la table `products` pour afficher le catalogue et la table `orders` pour afficher le suivi des commandes (ainsi que le lien de téléchargement du PDF depuis le bucket S3).
* **Vers `05-batch-ec2-spot` :** Le worker EC2 Spot met à jour la table `orders` (`status = SHIPPED`, `tracking_number`, `carrier_box`) et dépose le fichier PDF dans le bucket S3 `invoices`.

---

## 4. Comment personnaliser ce module (Pour le groupe)

* **Ajouter un produit au catalogue :** Dans [`main.tf`](./main.tf), ajoutez simplement une entrée dans le bloc `locals { initial_products = { ... } }` en précisant `dims_cm` (format `"LongueurxLargeurxHauteur"`) et `weight_kg`.
