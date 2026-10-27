# Module 04 : Serveur Web Front-End EC2 & Élasticité (Auto Scaling / ALB)

Ce dossier déploie la couche Front-End de la boutique ([`main.tf`](./main.tf) et [`src/app_server.py.tftpl`](./src/app_server.py.tftpl)).

---

## 1. Ce que déploie ce module

1. **Instance EC2 `t3.micro` (Amazon Linux 2023, Disque 8 Go `gp3` Free Tier) :**
   * Exécute un serveur web Python géré par **Systemd** (`cloudshop-front.service`) sur le **port 80**.
   * **Port 22 (SSH) fermé** dans le Security Group : aucun port d'administration n'est exposé.
2. **Rôle IAM `front-ec2-role` (Sans aucune clé AWS codée en dur) :**
   * Autorise uniquement :
     * `dynamodb:Scan` / `GetItem` sur les tables `products` et `orders`.
     * `lambda:InvokeFunction` sur la fonction `create-order`.
     * `s3:GetObject` sur le bucket `invoices` (pour générer les liens de téléchargement des factures PDF).
3. **Option Haute Disponibilité & Élasticité (`enable_autoscaling_alb`) :**
   * Par défaut (`false`), déploie **1 instance EC2** en 15 secondes pour le développement itératif rapide.
   * Si activée (`true`), déploie automatiquement un **Application Load Balancer (ALB)** Multi-AZ, un **Auto Scaling Group** (`min=1, desired=2, max=4`) et une **Target Tracking Scaling Policy** sur le CPU (> 60 %).

---

## 2. Comment ce module est connecté aux autres

* **Depuis `01-database-dynamodb` :** Lit en temps réel les articles du catalogue (`GET /api/products`) et la liste des commandes passées (`GET /api/orders`).
* **Vers `03-serverless-lambda` :** Lorsque le client clique sur **"Commander"**, le serveur Front-End appelle la fonction Lambda `create-order` via Boto3 (`POST /api/order`).
* **Depuis `05-batch-ec2-spot` (via DynamoDB & S3) :** Affiche automatiquement le format de carton calculé (`Colis S/M/L/XL`), le numéro de suivi transporteur et le lien **"📄 Ouvrir la Facture PDF"** dès que l'instance EC2 Spot a traité la commande.

---

## 3. Comment personnaliser ce module (Pour le groupe)

* **Modifier le design HTML/CSS ou les routes de la boutique :** Modifiez le fichier [`src/app_server.py.tftpl`](./src/app_server.py.tftpl).
* **Activer le Load Balancer + Auto Scaling Group pour la démo finale :** Passez `enable_autoscaling_alb = true` dans le fichier `variables.tf` à la racine du projet.
