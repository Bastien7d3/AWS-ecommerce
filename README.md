# Projet Cloud AWS — Boutique E-Commerce NÉOLIA (FISA 2026)

> **Projet académique :** FISA 2026 / Infrastructures cloud et virtualisation  
> **Enseignant :** Pr. Raouf Boulkroune  
> **Équipe projet :** Bastien BRUNEL, William PEREIRA, Lucas DEBRUYNE  
> **Région cible :** `eu-west-3` (Paris)  
> **Automatisation IaC :** Terraform (Multi-Module)

---

## 1. Sujet Officiel du Projet (Spécifications Client)

### Contexte & Spécifications
Concevoir et déployer une plateforme e-commerce moderne pour la marque cosmétique **NÉOLIA**. Les clients peuvent consulter un catalogue dynamique, passer des commandes en temps réel et recevoir leurs notifications transactionnelles.  
La plateforme doit être **hautement disponible, résiliente et optimisée FinOps**, tout en maintenant un coût d'exploitation proche de **0,00 €** en exploitant au maximum le **Free Tier d'AWS**.

### Exigences fonctionnelles
* **Pour les clients :**
  * Parcourir le catalogue cosmétique (Soins visage, corps, parfums).
  * Passer une commande avec mise à jour immédiate des stocks.
  * Recevoir un e-mail de confirmation instantané après l'achat.
* **Pour les opérations internes (Back-Office) :**
  * Traçabilité et persistance de toutes les commandes à des fins d'audit.
  * Déclenchement du traitement par lot (simulation colisage carton S/M/L/XL, facture PDF officielle et numéro de suivi transporteur).

### Exigences architecturales
* Architecture hybride combinant **IaaS (EC2)** et **Serverless (AWS Lambda)**.
* Découplage événementiel asynchrone (**Amazon SNS & SQS**).
* Déploiement 100 % automatisé via **Terraform**.

---

## 2. Architecture Globale (Fusion IaaS & Serverless)

L'architecture réunit l'élasticité IaaS (EC2 Front-End + Auto Scaling Group / ALB Multi-AZ), la réactivité Serverless (AWS Lambda + DynamoDB pour la prise de commande synchrone) et l'économie du modèle Batch asynchrone (Worker EC2 Spot éphémère).

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

## 3. Organisation Modulaire du Projet

Chaque brique de l'infrastructure est isolée dans un module réutilisable sous [`modules/`](./modules/) :

| Dossier Module | Services AWS Gérés | Rôle & Spécificités d'Architecture |
| :--- | :--- | :--- |
| **[`modules/00-auth-cognito/`](./modules/00-auth-cognito)** | **Amazon Cognito** (User Pool, App Client, Groupes) | Inscription et connexion sécurisée des clients. Domaine unique par compte AWS pour éliminer tout risque de conflit inter-comptes. Gestion des privilèges RBAC (`admin`). |
| **[`modules/01-database-dynamodb/`](./modules/01-database-dynamodb)** | **DynamoDB** (`products`, `orders`) + **Amazon S3** (`invoices`) | Catalogue produits pré-rempli, historique d'audit des commandes et archivage sécurisé des factures PDF. Tables configurées en mode `PROVISIONED` (100 % *Always Free*). |
| **[`modules/02-messaging-sns-sqs/`](./modules/02-messaging-sns-sqs)** | **Amazon SNS** (Topics + `FilterPolicy`) + **Amazon SQS** (Tampon) | Routage intelligent des e-mails transactionnels par `FilterPolicy` et rétention tampon des commandes jusqu'à 14 jours en attendant le passage du Worker Spot. |
| **[`modules/03-serverless-lambda/`](./modules/03-serverless-lambda)** | **AWS Lambda** (`create-order`) + **IAM Least Privilege** | Prise de commande synchrone : décrémentation atomique des stocks DynamoDB, enregistrement de la commande et injection parallèle dans SNS et SQS. |
| **[`modules/04-frontend-ec2/`](./modules/04-frontend-ec2)** | **EC2 `t3.micro`** + **ALB Multi-AZ** + **Auto Scaling** + **CloudFront** | Interface web responsive NÉOLIA, gestion des sessions, bascule automatique Multi-AZ (`eu-west-3a` / `eu-west-3b`) et distribution CDN Edge HTTPS. |
| **[`modules/05-batch-ec2-spot/`](./modules/05-batch-ec2-spot)** | **Launch Template EC2 Spot** + **Planning Cron** + **FPDF2** | Zéro instance active au repos (`Scale-to-Zero`). Démarre périodiquement (02h00 UTC) ou à la demande via l'admin web, génère les factures PDF et s'auto-détruit (`Terminated`). |

---

## 4. Zoom Technique : Worker Spot Éphémère & Routage SNS

### A. Le concept du *Scale-to-Zero* sur EC2 Spot
* **Zéro euro au repos :** Le module `05-batch-ec2-spot` ne maintient aucune instance active inutilement. La capacité désirée par défaut est `desired_capacity = 0`.
* **Déclenchement flexible :**
  1. *Automatique (Périodique) :* Réveil programmé toutes les nuits à 02h00 UTC via règle Auto Scaling.
  2. *À la demande (Administrateur) :* Déclenchement instantané via le bouton de l'espace administration web.
* **Auto-destruction matérielle :** Le worker dépile les messages SQS, génère les PDF dans S3, envoie le lien transporteur, puis déclenche `shutdown -h now`. Grâce à `instance_initiated_shutdown_behavior = "terminate"`, l'instance et son volume EBS sont immédiatement supprimés.

### B. Ciblage transactionnel par e-mail (`FilterPolicy` SNS)
Pour éviter qu'un client ne reçoive les commandes d'un tiers sur un Topic commun :
* Chaque souscription client porte un filtre d'abonnement : `{"customer_email": ["client@domaine.fr"]}`.
* Les publications Lambda et Spot attachent l'en-tête `MessageAttributes = {"customer_email": email_client}`.
* Amazon SNS applique le filtrage côté infrastructure et n'achemine le message qu'au destinataire exact.

---

## 5. Analyse FinOps & Seuil de Rentabilité

> L'étude chiffrée complète est disponible dans **[`ANALYSE_COUTS_REELS_FINOPS.md`](./ANALYSE_COUTS_REELS_FINOPS.md)**.

* **Break-Even Point (Génération PDF) :**
  * Hors offre gratuite : l'EC2 Spot devient plus économique qu'une Lambda dès **12 000 factures/mois**.
  * Avec le quota gratuit (*Always Free*) : la Lambda couvre les factures jusqu'à **266 000 factures/mois**. Au-delà, ou pour s'affranchir de la limite stricte de **15 minutes** lors de batchs comptables volumineux, l'instance Spot éphémère est la solution la plus pérenne.
* **Impact du Réseau VPC :** Une NAT Gateway standard génère ~40 $ / mois de coûts fixes incompressibles (0,05 $/h + adresses IPv4 publiques). Notre architecture maximise le Free Tier en éliminant les composants sur-dimensionnés.

---

## 6. 🚀 Déploiement & Évaluation en 1 Clic (Espace Enseignant)

Des scripts automatisés gèrent l'intégralité du cycle de vie du projet sur n'importe quel compte AWS sans aucune configuration manuelle préalable.

### A. Déploiement Automatisé

#### Sur Linux / macOS :
```bash
chmod +x deploy_eval.sh destroy_eval.sh
./deploy_eval.sh
```

#### Sur Windows (PowerShell) :
```powershell
.\deploy_eval.ps1
```

**Ce que réalise le script automatiquement :**
1. Contrôle votre session et vos droits AWS (`aws sts get-caller-identity`).
2. Isole l'état Terraform en local (aucun bucket S3 distant requis).
3. Déploie l'ensemble de l'architecture AWS (`terraform apply`).
4. Crée automatiquement le compte administrateur dans Amazon Cognito :
   * **Identifiant :** `admin@neolia.com`
   * **Mot de passe :** `Neolia2026!Admin`
5. Affiche l'URL publique de la boutique.

---

### B. Scénario de Test Rapide (3 minutes chrono)

| Étape | Action à réaliser | Ce qui est validé sous le capot |
|---|---|---|
| **1. Parcours Client** | Ouvrir l'URL de la boutique, ajouter un produit (ex: *Gel Nettoyant Minéral*) au panier et valider l'achat. | Disponibilité Front-End, intégration dynamique. |
| **2. Traitement Serverless** | Constater l'affichage immédiat du numéro de commande et la mise à jour du stock. | Exécution **Lambda**, écriture atomique **DynamoDB**, publication **SNS** et buffer **SQS**. |
| **3. Espace Administration** | Se connecter sur `/admin` avec `admin@neolia.com` / `Neolia2026!Admin`. Observer la commande dans la file d'attente. | Authentification **Cognito** et contrôle d'accès RBAC. |
| **4. Batch Spot Éphémère** | Cliquer sur le bouton **« Lancer l'instance EC2 Spot »**. | Lancement d'une instance **EC2 Spot**, vidage de la file SQS, génération du PDF dans **S3**, puis **auto-destruction (Scale-to-Zero)**. |

---

### C. Nettoyage Complet (0 € de frais résiduels)

Pour détruire 100 % des ressources créées à l'issue de l'évaluation :

```bash
# Linux / macOS :
./destroy_eval.sh

# Windows (PowerShell) :
.\destroy_eval.ps1
```
