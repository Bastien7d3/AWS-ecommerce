# Projet Cloud AWS — Boutique E-Commerce Haute Disponibilité (FISA 2026)

> **Projet académique :** FISA 2026 / Infrastructures cloud et virtualisation  
> **Enseignant :** Pr. Raouf Boulkroune  
> **Auteur :** Bastien (`Bastien7d3`) | **Compte AWS :** `689505268069` | **Région :** `eu-west-3` (Paris)  
> **Automatisation IaC :** Terraform

---

## 1. Sujet Officiel du Projet (Spécifications Client)

### Contexte & Spécifications
Réaliser une boutique en ligne où les clients peuvent consulter un catalogue, passer des commandes et recevoir des notifications de confirmation en temps réel.  
La plateforme doit être **évolutive, rentable et résiliente**. Elle sera construite à partir des services gérés par AWS dans le cadre de l'offre **Free Tier**.  
Le système doit gérer l'interface utilisateur, les commandes et le traitement des commandes.  
Le site doit être **hautement disponible**. Adapter votre solution pour **AWS Free Tier** en éliminant certaines fonctions pour maintenir le coût à zéro.

### Exigences fonctionnelles
* **Pour les clients :**
  * Parcourir un catalogue de produits via une interface Web.
  * Passer une commande pour un ou plusieurs produits.
  * Recevoir un message de confirmation après avoir passé leur commande.
* **Pour les systèmes internes de l'entreprise :**
  * Enregistrer toutes les commandes à des fins d'audit et de reporting.
  * Déclencher les opérations internes de traitement des commandes (emballage, simulation d'expédition avec numéro de suivi transporteur et facture PDF).

### Exigences architecturales
* Utiliser **AWS Serverless** et **Compute EC2**.
* Inclure des modèles événementiels (**SNS**) et aborder le streaming (**Kafka, MSK**).
* Utiliser **Terraform** pour l'automatisation intégrale de l'infrastructure.

---

## 2. Architecture du Projet (Hybride Free Tier à 0,00 €)

L'architecture réunit l'élasticité IaaS (EC2 Front-End + Auto Scaling Group / ALB), la réactivité Serverless (AWS Lambda + DynamoDB pour la prise de commande synchrone) et l'économie du modèle Batch asynchrone (Worker EC2 Spot éphémère).

```mermaid
flowchart TB
    Client["Client Web (Navigateur / Mobile)"]

    subgraph Front_Tier["1. Module 04 : Front-End EC2 et Elasticite (IaaS)"]
        ALB["Application Load Balancer (Public Multi-AZ)"]
        subgraph ASG["Auto Scaling Group Web (min=1, desired=2, max=4)"]
            EC2_A["EC2 Web Zone A (t3.micro)"]
            EC2_B["EC2 Web Zone B (t3.micro)"]
        end
        CW_CPU["CloudWatch Alarm (CPU > 60%)"]
        CW_CPU -.->|Scale-Out / Scale-In| ASG
        ALB --> EC2_A & EC2_B
    end

    subgraph Serverless_Order["2. Modules 01 et 03 : Lambda et DynamoDB (Serverless)"]
        Lambda["AWS Lambda: CreateOrder (Python 3.12)"]
        DDB_Catalog[("DynamoDB: Products")]
        DDB_Orders[("DynamoDB: Orders")]
    end

    subgraph Messaging_Buffer["3. Module 02 : Notifications SNS et File SQS"]
        SNS_Order(("Amazon SNS: OrderConfirmation"))
        SQS_Batch[["Amazon SQS: orders-batch-queue (Retention 14j)"]]
    end

    subgraph Async_Spot_Batch["4. Module 05 : Worker Batch EC2 Spot et S3 PDF"]
        Spot["Instance EC2 Spot Worker (t3.micro Spot)"]
        S3_Bucket[("Amazon S3: Factures PDF et Rapports Audit")]
        SNS_Ship(("Amazon SNS: ShippingNotification"))
    end

    Client -->|1. Navigation et Panier| ALB
    EC2_A & EC2_B -->|2. Validation Commande| Lambda
    Lambda -->|3. Verifie stock et decremente| DDB_Catalog
    Lambda -->|4. Insere commande - Statut PENDING| DDB_Orders
    Lambda -->|5a. Mail 1: Confirmation immediate| SNS_Order
    SNS_Order -.->|Mail client| Client
    Lambda -->|5b. Empile pour le batch| SQS_Batch

    SQS_Batch -->|6. Depile la commande| Spot
    Spot -->|7a. Calcul carton S/M/L/XL et No Suivi| DDB_Orders
    Spot -->|7b. Genere Facture PDF officielle| S3_Bucket
    Spot -->|7c. Mise a jour statut: SHIPPED| DDB_Orders
    Spot -->|8. Mail 2: No Suivi transporteur et Lien PDF| SNS_Ship
    SNS_Ship -.->|Mail d expedition| Client
    Spot -.->|9. Extinction automatique Scale-to-Zero| Spot
```

---

## 3. Organisation Modulaire du Projet (Les 5 Grandes Parties)

Chaque partie de l'architecture possède son propre dossier dans [`modules/`](./modules/) avec son code Terraform et son **guide explicatif dédié** :

| Dossier Module | Services AWS Gérés | Rôle & Connexions | Documentation Détaillée |
| :--- | :--- | :--- | :--- |
| **[`modules/01-database-dynamodb/`](./modules/01-database-dynamodb)** | **DynamoDB** (`products`, `orders`) + **Amazon S3** (`invoices`) | Stocke le catalogue produits (pré-rempli), l'historique des commandes et les factures PDF. Configuré en mode `PROVISIONED` (5 RCU / 5 WCU = 100 % *Always Free*). | [EXPLICATIONS_DYNAMODB_S3.md](./modules/01-database-dynamodb/EXPLICATIONS_DYNAMODB_S3.md) |
| **[`modules/02-messaging-sns-sqs/`](./modules/02-messaging-sns-sqs)** | **Amazon SNS** (2 Topics) + **Amazon SQS** (File batch) | Envoie les notifications e-mail en temps réel (SNS) et conserve les commandes en attente jusqu'à 14 jours (SQS) pour découpler la Lambda du Worker EC2 Spot. | [EXPLICATIONS_SNS_SQS.md](./modules/02-messaging-sns-sqs/EXPLICATIONS_SNS_SQS.md) |
| **[`modules/03-serverless-lambda/`](./modules/03-serverless-lambda)** | **AWS Lambda** (`create-order`) + **IAM** | Appelée par le Front-End EC2 lors d'un achat : décrémente le stock dans DynamoDB, crée la commande (`PENDING`), notifie SNS et pousse dans SQS. | [EXPLICATIONS_LAMBDA.md](./modules/03-serverless-lambda/EXPLICATIONS_LAMBDA.md) |
| **[`modules/04-frontend-ec2/`](./modules/04-frontend-ec2)** | **EC2 `t3.micro`** + **ALB** + **Auto Scaling Group** | Héberge l'interface web de la boutique (Catalogue, bouton Commander via Lambda, suivi en temps réel des colis et téléchargement du PDF depuis S3). | [EXPLICATIONS_FRONTEND_EC2.md](./modules/04-frontend-ec2/EXPLICATIONS_FRONTEND_EC2.md) |
| **[`modules/05-batch-ec2-spot/`](./modules/05-batch-ec2-spot)** | **EC2 Spot `t3.micro`** + **FPDF2** | Dépile SQS, calcule le carton transporteur optimal (`Colis S, M, L, XL`), génère la facture PDF sur S3, passe la commande à `SHIPPED` dans DynamoDB et envoie le N° de suivi via SNS. | [EXPLICATIONS_BATCH_SPOT.md](./modules/05-batch-ec2-spot/EXPLICATIONS_BATCH_SPOT.md) |

---

## 4. Analyse FinOps & Seuil de Rentabilité (Break-Even Point)

### Comparatif des coûts (Région eu-west-3 Paris)
* **Coût de l'EC2 Spot en batch éphémère (2h / nuit = 60h / mois) :**
  * Calcul Spot `t3.micro` : 60 h x 0,0031 $/h = **0,186 $/mois**
  * Disque EBS `gp3` (8 Go) : **0,70 $/mois**
  * **Total mensuel fixe du worker : environ 0,89 $/mois**
* **Coût sur AWS Lambda (génération PDF 3s à 512 Mo de RAM) :**
  * Environ **0,0000202 $ par commande**

### Seuil de rentabilité mathématique
* `Seuil = 0,89 $ / 0,0000202 $` = **environ 44 000 commandes / mois** (~1 450 commandes / jour)
* **En dessous de 44 000 commandes/mois :** Le Serverless (Lambda) est le plus économique, et les 266 000 premières exécutions sont couvertes à **0,00 €** par l'offre *Always Free* (400 000 Go-secondes).
* **Au-delà de 44 000 commandes/mois :** L'EC2 Spot éphémère est nettement plus avantageuse (-75 % à 200 000 commandes) et s'affranchit de la limite stricte des **15 minutes d'exécution maximum** imposée par AWS Lambda.

---

## 5. Commandes de Déploiement & Destruction (Environnement Éphémère)

À la racine du dépôt :

```powershell
# 1. Initialiser les modules et providers Terraform
terraform init

# 2. Vérifier la syntaxe et déployer toute l'architecture connectée
terraform validate
terraform apply -auto-approve

# 3. Détruire intégralement l'infrastructure après les tests (Garantie 0,00 €)
terraform destroy -auto-approve
```
