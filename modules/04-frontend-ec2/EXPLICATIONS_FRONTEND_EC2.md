# Module 04 : Serveur Web Front-End EC2 & Élasticité (Auto Scaling / ALB)

Ce dossier déploie la couche Front-End de la boutique et le tableau de bord d'administration ([`main.tf`](./main.tf) et [`src/app_server.py.tftpl`](./src/app_server.py.tftpl)).

---

## 1. Ce que déploie ce module

1. **Instance EC2 `t3.micro` (Amazon Linux 2023, Disque 8 Go `gp3` Free Tier) :**
   * Exécute un serveur web Python géré par **Systemd** (`cloudshop-front.service`) sur le **port 80**.
   * **Port 22 (SSH) fermé** dans le Security Group : aucun port d'administration n'est exposé.
2. **Rôle IAM `front-ec2-role` (Sans aucune clé AWS codée en dur) :**
   * Autorise uniquement :
     * `dynamodb:Scan` / `GetItem` sur les tables `products` et `orders`.
     * `lambda:InvokeFunction` sur la fonction `create-order`.
     * `s3:GetObject` sur le bucket `invoices` (pour générer les liens pré-signés des factures PDF).
     * `sns:Subscribe` et `sns:SetSubscriptionAttributes` (pour abonner l'e-mail d'un client avec `FilterPolicy`).
     * `sqs:GetQueueAttributes` (pour afficher le nombre de commandes en attente de batch dans SQS).
     * `ec2:RunInstances` et `ec2:DescribeInstances` + `iam:PassRole` (pour permettre à l'admin de lancer manuellement une instance EC2 Spot à la demande depuis le Launch Template).
3. **Option Haute Disponibilité & Élasticité (`enable_autoscaling_alb`) :**
   * Par défaut (`false`), déploie **1 instance EC2** en 15 secondes pour le développement itératif rapide.
   * Si activée (`true`), déploie automatiquement un **Application Load Balancer (ALB)** Multi-AZ, un **Auto Scaling Group** (`min=1, desired=2, max=4`) et une **Target Tracking Scaling Policy** sur le CPU (> 60 %).

---

## 2. Les Routes API du Serveur Front-End

* `GET /api/products` : Lit les articles du catalogue dans `cloudshop-products`.
* `POST /api/subscribe` : Abonne l'adresse e-mail saisie par le client aux 2 Topics SNS (`order-confirmation` et `shipping-notification`) avec une `FilterPolicy` `{"customer_email": ["..."]}` afin qu'il ne reçoive que ses propres commandes.
* `POST /api/order` : Appelle la fonction Lambda `create-order` en lui transmettant `product_id`, `qty`, `customer_name` et `customer_email`.
* `GET /api/spot-status` : Affiche en temps réel le nombre de messages en attente dans la file SQS et l'état des instances EC2 Spot récentes (`pending`, `running`, `shutting-down`, `terminated`).
* `POST /api/launch-spot` : Permet à l'administrateur de créer à la demande une instance **EC2 Spot** à partir du Launch Template (`ec2.run_instances`). L'instance démarre, vide la file SQS, génère les factures PDF sur S3, puis s'auto-détruit (`shutdown -h now` -> `terminated`).
* `GET /api/orders` : Liste les commandes DynamoDB et génère des liens pré-signés S3 temporaires (valables 1 heure) vers les factures PDF.

---

## 3. Comment personnaliser ce module (Pour le groupe)

* **Modifier le design HTML/CSS ou les routes de la boutique :** Modifiez le fichier [`src/app_server.py.tftpl`](./src/app_server.py.tftpl).
* **Activer le Load Balancer + Auto Scaling Group pour la démo finale :** Passez `enable_autoscaling_alb = true` dans le fichier `variables.tf` à la racine du projet.
