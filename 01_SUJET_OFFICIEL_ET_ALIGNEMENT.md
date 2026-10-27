# Sujet Officiel FISA 2026 & Grille d'Alignement du Projet

**Cours :** Infrastructures Cloud et Virtualisation (FISA 2026)  
**Enseignant :** Pr. Raouf Boulkroune

---

## 1. Rappel Intégral de la Consigne du Professeur

### Contexte / Spécifications du client
Réaliser une boutique en ligne où les clients peuvent consulter un catalogue, passer des commandes et recevoir des notifications de confirmation en temps réel.
La plateforme doit être évolutive, rentable et résiliente. Elle sera construite à partir des services gérés par AWS dans le cadre de l'offre **Free Tier**.
Le système doit gérer l'interface utilisateur, les commandes et le traitement des commandes.
Le site doit être **hautement disponible**. **Proposer 2 solutions différentes**, l'une basée sur des machines virtuelles et l'autre à base de services Serverless. Adapter votre solution pour AWS Free Tier en éliminant certaines fonctions pour maintenir le coût à zéro.

### Exigences fonctionnelles
Les clients peuvent :
* Parcourir un catalogue de produits via une interface Web.
* Passer une commande pour un ou plusieurs produits.
* Recevoir un message de confirmation après avoir passé leur commande.

Les systèmes internes de l'entreprise doivent :
* Enregistrer toutes les commandes à des fins d'audit et de reporting.
* Déclencher les opérations internes de traitement des commandes (emballage, simulation d'expédition).

### Exigences d'architecture
* Utiliser **AWS Serverless** et **Compute EC2**.
* Inclure des modèles événementiels (**SNS**) et si possible de streaming (**Kafka, MSK**).
* Utiliser **Terraform** pour l'automatisation de l'infrastructure.

### Livrables attendus
1. **Présentation orale** avec schémas d'architecture, comparaison des solutions (y compris les solutions optimales hors budget présentées sans être implémentées) et démonstration.
2. **Rapport écrit** détaillant les choix techniques, la gestion du budget Free Tier et le déroulement du projet.
3. **Code Terraform** reproductible avec explication du lancement et des scénarios de test.

---

## 2. Tableau d'Alignement : Comment Notre Projet Répond à Chaque Point

| Exigence du Sujet | Notre Réponse Technique & Académique | Statut |
| :--- | :--- | :---: |
| **Proposer 2 solutions (VM vs Serverless)** | • **Solution 1 (100 % VM)** : ALB + EC2 Auto Scaling + RDS Multi-AZ + MSK.<br>• **Solution 2 (100 % Serverless)** : CloudFront + S3 + API Gateway + Lambda + DynamoDB + SNS/SQS. | Documenté & Schématisé |
| **Adapter au Free Tier (Coût 0 €)** | Élimination de **MSK** (~200 $/mois), **RDS Multi-AZ** (> 750h) et **NAT Gateway** (~35 $/mois). Remplacement par **DynamoDB Provisioned (5 RCU/WCU)** + **SNS/SQS** + **EC2 éphémère**. | Chiffré & Justifié |
| **Haute Disponibilité (HA)** | **Application Load Balancer (ALB)** répartissant le trafic sur **2 instances EC2 (`t3.micro`)** dans 2 zones de disponibilité (`eu-west-3a` et `eu-west-3b`). | Intégré |
| **Utiliser Serverless ET Compute EC2** | • **EC2 Web** (Front-End HA) + **EC2 Spot** (Batch logistique & PDF).<br>• **AWS Lambda** (Prise de commande transactionnelle) + **DynamoDB**. | Intégré |
| **Notifications temps réel (SNS)** | • **Mail 1 (SNS)** : Confirmation immédiate de prise de commande.<br>• **Mail 2 (SNS)** : Notification d'expédition avec **N° de suivi transporteur** et lien de la facture PDF. | Validé en PoC |
| **Audit & Opérations internes (Emballage, Expédition)** | • **Audit** : Historisation dans DynamoDB + rapports JSON et factures PDF archivés sur **Amazon S3**.<br>• **Emballage & Expédition** : Calcul automatique du carton (`Colis S, M, L, XL`) et passage du statut à `PACKAGED` puis `SHIPPED` par le Worker EC2 Spot. | Validé en PoC |
| **Surveillance & Élasticité** | **Alarmes CloudWatch** sur la file SQS (`ApproximateNumberOfMessagesVisible`) avec seuils réglables par l'Admin Cloud pour lancer 1 ou 2 instances EC2 Spot (split du batch en 2). | Validé en PoC |
