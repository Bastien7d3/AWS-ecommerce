# Analyse FinOps & Coûts Réels AWS — Projet CloudShop (FISA 2026)

> **Compte AWS audité :** `689505268069` — **Région :** `eu-west-3` (Paris)
> **Coût réel facturé à date (AWS Cost Explorer) :** **0,00 $** (100 % couvert par le Free Tier AWS).

---

## 1. Détail Module par Module : Configuration Terraform, Consommation Réelle & Où la consulter sur AWS

### Module 00 : Authentification Client (`modules/00-auth-cognito`)
* **Ressources Terraform ([`modules/00-auth-cognito/main.tf`](./modules/00-auth-cognito/main.tf)) :**
  * `aws_cognito_user_pool.pool` (`cloudshop-user-pool`, ID : `eu-west-3_oNvBDPYNy`)
  * `aws_cognito_user_pool_client.client` (`cloudshop-app-client`)
  * `aws_cognito_user_pool_domain.main` (`cloudshop-auth-fisa2026`)
* **Consommation réelle relevée sur AWS :**
  * **2 utilisateurs inscrits** (MAU = *Monthly Active Users*).
  * Coût réel : **0,00 $**.
* **Grille tarifaire AWS (`eu-west-3`) :**
  * **Always Free (Gratuit à vie) :** Jusqu'à **50 000 utilisateurs actifs / mois (MAU)**.
  * Au-delà de 50 000 MAU : **0,0055 $ par MAU** (de 50 001 à 100 000 MAU).

---

### Module 01 : Base de Données NoSQL & Stockage Factures (`modules/01-database-dynamodb` + Backend S3)
* **Ressources Terraform ([`modules/01-database-dynamodb/main.tf`](./modules/01-database-dynamodb/main.tf) & [`main.tf`](./main.tf)) :**
  * Table DynamoDB `cloudshop-products` : Mode `PROVISIONED` (**5 RCU / 5 WCU**).
  * Table DynamoDB `cloudshop-orders` : Mode `PROVISIONED` (**5 RCU / 5 WCU**).
  * Table DynamoDB `cloudshop-tfstate-locks` (verrouillage Terraform) : Mode `PAY_PER_REQUEST` -> usage vraiment peu fréquent mais pertinent de payer à l'usage pour laisser de la place à une éventuelle extension des autres bases de données.
  * Bucket S3 `cloudshop-invoices-689505268069` (Factures PDF + scripts Python).
  * Bucket S3 `cloudshop-tfstate-fisa2026-unique` (État partagé `terraform.tfstate`).
* **Consommation réelle relevée sur AWS :**
  * **DynamoDB :** 10 RCU et 10 WCU provisionnés au total sur le projet (sur les 25 RCU / 25 WCU gratuits) ; `1 730 unités` consommées dans Cost Explorer -> **0,00 $**.
  * **Amazon S3 :**
    * `cloudshop-invoices-689505268069` : **14 objets** pour **68,4 Ko** (`68 444 octets`, ~2,5 Ko par facture PDF).
    * `cloudshop-tfstate-fisa2026-unique` : **1 objet** pour **123,5 Ko** (`123 457 octets`).
    * Total requêtes S3 dans Cost Explorer : `1 999 requêtes` -> **0,000002 $ (~0,00 €)**.
* **Grille tarifaire AWS (`eu-west-3`) :**
  * **DynamoDB (*Always Free*) :** 25 Go de stockage + 25 WCU + 25 RCU gratuits à vie (permettent jusqu'à **200 millions de requêtes/mois**). Au-delà en mode *On-Demand* : **1,34 $ / million d'écritures** et **0,268 $ / million de lectures**.
  * **Amazon S3 (*Free Tier 12 mois*) :** 5 Go de stockage Standard + 20 000 `GET` + 2 000 `PUT` gratuits/mois. Au-delà : **0,024 $ / Go / mois** ; **0,0053 $ / 1 000 requêtes `PUT`** ; **0,00042 $ / 1 000 requêtes `GET`**.

---

### Module 02 : Bus Événementiel & File d'Attente (`modules/02-messaging-sns-sqs`)
* **Ressources Terraform ([`modules/02-messaging-sns-sqs/main.tf`](./modules/02-messaging-sns-sqs/main.tf)) :**
  * Topic SNS `cloudshop-order-confirmation` (avec abonnement e-mail filtré par `FilterPolicy`).
  * Topic SNS `cloudshop-shipping-notification`.
  * File SQS Standard `cloudshop-orders-batch-queue` (rétention : 14 jours = `1 209 600 s`, *visibility timeout* : `120 s`).
* **Consommation réelle relevée sur AWS :**
  * **SQS :** **16 messages envoyés**, **12 messages reçus** (`27 appels API` au total dans Cost Explorer) -> **0,00 $**.
  * **SNS :** **28 publications**, **17 notifications e-mail délivrées** -> **0,00 $**.
* **Grille tarifaire AWS (`eu-west-3`) :**
  * **Amazon SQS (*Always Free*) :** **1 000 000 de requêtes / mois gratuites à vie**. Au-delà : **0,40 $ par million de requêtes**.
  * **Amazon SNS (*Always Free*) :** **1 000 000 de publications** + **1 000 notifications e-mail / mois gratuites à vie**. Au-delà de 1 000 e-mails/mois : **2,00 $ par 100 000 e-mails** (soit `0,00002 $ / e-mail`).
---

### Module 03 : Cœur Transactionnel Serverless (`modules/03-serverless-lambda`)
* **Ressources Terraform ([`modules/03-serverless-lambda/main.tf`](./modules/03-serverless-lambda/main.tf)) :**
  * Fonction Lambda `cloudshop-create-order` : Runtime `python3.12`, **RAM = 128 Mo**, Timeout = `15 s`, Taille du code = `1 839 octets`.
* **Consommation réelle relevée sur AWS (CloudWatch & Cost Explorer) :**
  * **16 invocations** réalisées lors de nos tests.
  * **Durée moyenne réelle d'exécution :** **603,4 ms** (Maximum : `845,5 ms`).
  * **Consommation totale de calcul :** `2,089 Go-secondes` (sur 400 000 Go-s gratuites) -> **0,00 $**.
* **Grille tarifaire AWS (`eu-west-3`) :**
  * **AWS Lambda (*Always Free*) :** **1 000 000 de requêtes / mois** + **400 000 Go-secondes / mois** gratuits à vie.
    * À **128 Mo de RAM** et **603 ms** par commande, 1 commande consomme `0,125 Go x 0,603 s = 0,0754 Go-s`.
    * L'offre *Always Free* couvre donc gratuitement jusqu'à **5 300 000 exécutions de `create-order` en Go-s** (plafonnée à **1 000 000 de requêtes gratuites/mois**).
  * Au-delà du Free Tier : **0,20 $ / million de requêtes** + **0,0000166667 $ par Go-seconde**.

---

### Module 04 : Serveur Web Front-End EC2 & Élasticité (`modules/04-frontend-ec2`)
(à compléter)

---

### Module 05 : Worker Batch EC2 Spot Éphémère (`modules/05-batch-ec2-spot`)
* **Ressources Terraform ([`modules/05-batch-ec2-spot/main.tf`](./modules/05-batch-ec2-spot/main.tf)) :**
  * `aws_launch_template.spot_worker_lt` (`t3.micro`, `instance_initiated_shutdown_behavior = "terminate"`, EBS `8 Go gp3` avec `delete_on_termination = true`).
  * `aws_autoscaling_group.spot_periodic_asg` (`desired_capacity = 0` au repos, réveil planifié à `02h00 UTC` via `aws_autoscaling_schedule` ou lancement manuel à la demande).
* **Prix Spot réels relevés en direct sur AWS `eu-west-3` (via `ec2:DescribeSpotPriceHistory`) :**
  * `t3.micro` Spot :
    * `eu-west-3c` : **0,0040 $ / heure** (contre **0,0118 $/h** en On-Demand, soit **-66,1 % d'économie**)
    * `eu-west-3a` : **0,0043 $ / heure** (**-63,6 %**)
    * `eu-west-3b` : **0,0047 $ / heure** (**-60,2 %**)
  * `t3.small` Spot :
    * `eu-west-3c` : **0,0078 $ / heure** (contre **0,0236 $/h** en On-Demand, soit **-66,9 % d'économie**)
* **Coût réel d'un cycle Batch Spot (avec auto-destruction `terminate`) :**
  * Comme l'instance et son disque EBS 8 Go sont **détruits dès la fin du batch** (`shutdown -h now` -> `terminated`), **on ne paie le disque EBS et le CPU que pendant les minutes où le batch tourne** !
  * Pour un batch de **10 minutes par nuit** (soit **5 heures par mois** au total) en `eu-west-3c` :
    * Calcul EC2 Spot `t3.micro` : `5 h x 0,0040 $/h` = **0,020 $ / mois**
    * Disque EBS `gp3` 8 Go éphémère (5 h sur 730 h) : `0,70 $ x (5 / 730)` = **0,0048 $ / mois**
    * **Coût total réel du Worker Spot auto-destructeur : ~0,025 $ / mois (soit 2,5 centimes par mois !)**
  * Même pour un gros batch lourd de **2 heures par nuit** (60 heures / mois) :
    * Calcul EC2 Spot `t3.micro` : `60 h x 0,0040 $/h` = **0,24 $ / mois**
    * Disque EBS `gp3` 8 Go éphémère (60 h sur 730 h) : `0,70 $ x (60 / 730)` = **0,058 $ / mois**
    * **Total mensuel (2h/nuit) : ~0,30 $ / mois !**


---

## 2. Comparaison Financière : Notre Architecture Hybride vs Architecture Full Serverless selon le Nombre de Clients

Pour déterminer quelle architecture est financièrement la plus judicieuse selon la taille de l'entreprise (en **région `eu-west-3` Paris**, **hors Free Tier 12 mois** pour évaluer la rentabilité pérenne à long terme), comparons deux architectures :

1. **Architecture A — Full Serverless :**
   * **Front-End :** Site statique sur **Amazon S3 + CloudFront** + **Amazon API Gateway (HTTP API)** (`1,00 $ / million d'appels`) + **AWS Lambda** (`create-order`).
   * **Back-Office (Colisage + Facture PDF) :** Une **2e fonction AWS Lambda** (`generate-invoice`, 512 Mo de RAM, 3 secondes par facture PDF).
   * **Données & Messaging :** DynamoDB + SQS + SNS + S3 + Cognito (identiques dans les deux architectures).
2. **Architecture B — Notre Architecture Hybride (EC2 Front + Lambda + Worker Batch EC2 Spot Éphémère) :**
   * **Front-End :** Instance **EC2 `t3.micro`** (ou **ALB + Auto Scaling Group** lors des fortes charges).
   * **Prise de commande :** **AWS Lambda** (`create-order`) + **SQS** + **SNS**.
   * **Données & Messaging :** DynamoDB + SQS + SNS + S3 + Cognito
   * **Back-Office (Colisage + Facture PDF) :** **Worker Batch EC2 Spot Éphémère** (`0,0040 $/h`, détruit automatiquement dès que la file SQS est vide).

---

### A. Comparaison de la Brique n°1 : Le Traitement Batch (Facturation PDF & Colisage) — Lambda vs EC2 Spot Éphémère

* **Sur AWS Lambda (Full Serverless) :**
  * Générer un PDF avec `fpdf2`, l'uploader sur S3 et mettre à jour DynamoDB demande **512 Mo de RAM (`0,5 Go`)** pendant **3 secondes** = **1,5 Go-seconde par commande**.
  * Coût unitaire hors Free Tier : `1,5 Go-s x 0,00001667 $ + 0,0000002 $ (requête)` = **0,0000252 $ par commande** (soit **2,52 $ pour 100 000 commandes**).
  * **Limite technique dure :** Une fonction Lambda a un **timeout strict de 15 minutes maximum**. Si l'entreprise doit générer un rapport comptable consolidé ou retraiter un lot massif de plus de 15 minutes, Lambda échoue (`Task timed out after 900.00 seconds`).
* **Sur notre Worker EC2 Spot Éphémère (`t3.micro` à `0,0040 $/h` qui s'auto-détruit après le batch) :**
  * Sur une instance EC2 déjà chaude (sans *cold start* à chaque commande), le script Python en boucle traite **1 commande toutes les 0,15 seconde** (soit **24 000 commandes / heure**).
  * Coût horaire tout compris (Spot `0,0040 $/h` + EBS `gp3` proratisé `0,0010 $/h`) = **0,0050 $ / heure**, soit **0,00000021 $ par commande** (**120 fois moins cher par commande que Lambda** dès que l'instance traite un lot continu !).
  * Même en comptant un réveil quotidien fixe de **2h par nuit (60h/mois)** pour absorber les lots et rapports d'audit : le coût fixe est de **0,30 $ / mois** (avec destruction EBS) à **0,94 $ / mois** (si volume EBS conservé).
  * **Seuil de rentabilité du Batch (Break-Even Point) :**
    * Dès **12 000 commandes / mois** (ou dès qu'un traitement par lot dépasse 15 minutes), **le Worker EC2 Spot éphémère bat financièrement et techniquement AWS Lambda**.

---

### B. Comparaison de la Brique n°2 : Le Front-End Web — EC2 / ALB vs S3 + CloudFront + API Gateway

Supposons qu'un **client actif** effectue en moyenne **20 pages vues / appels API** par visite et passe **1 commande**.

* **En Full Serverless (S3 + CloudFront + API Gateway HTTP) :**
  * Coût fixe au repos (0 client) : **0,00 $ / mois**.
  * Coût variable : API Gateway HTTP coûte **1,00 $ par million de requêtes** + CloudFront (~0,085 $/Go transféré).
  * Pour **10 000 clients/mois** (200 000 appels API) : **~0,25 $ / mois**.
  * Pour **500 000 clients/mois** (10 millions d'appels API + 50 Go de trafic) : **~14,25 $ / mois**.
  * Pour **5 000 000 de clients/mois** (100 millions d'appels API + 500 Go de trafic) : **~142,50 $ / mois**.
* **Sur EC2 Front-End :**
  * **Mode 1 EC2 `t3.micro` seule (`enable_autoscaling_alb = false`) :**
    * Pendant les 12 premiers mois (Free Tier) : **0,00 $ / mois**.
    * Hors Free Tier : **9,31 $ / mois fixes** (`8,61 $` EC2 + `0,70 $` EBS), quel que soit le nombre de requêtes (jusqu'à saturation CPU ~50 req/s).
  * **Mode Haute Disponibilité Multi-AZ (`enable_autoscaling_alb = true` : ALB + 2 EC2 `t3.micro`) :**
    * Coût de base hors Free Tier : **~36,36 $ / mois** (`17,74 $` d'ALB + `2 x 9,31 $` d'instances EC2).

---

### C. Tableau Décisionnel Global : Quelle architecture choisir selon le nombre de clients / mois ?

*(Coûts mensuels totaux estimés en `eu-west-3`, hors période d'essai 12 mois mais en conservant les paliers **Always Free** permanents de Lambda, DynamoDB, SQS, SNS et Cognito)*

| Volume Mensuel | Nb de Commandes / mois | Appels API / mois | Coût Mensuel **Full Serverless** (API Gateway + 2 Lambdas) | Coût Mensuel **Hybride Monolithique** (1 EC2 Front + Lambda + Spot) | Coût Mensuel **Hybride HA Multi-AZ** (ALB + ASG 2 EC2 + Lambda + Spot) | Solution la plus judicieuse financièrement |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Palier 1 : Lancement / TPE**<br>*(0 à 5 000 clients)* | 0 à 5 000 | 0 à 100 000 | **0,00 $ à 0,15 $ / mois**<br>*(Lambda/DDB/Cognito couverts par Always Free)* | **9,33 $ / mois**<br>*(0,00 $ la 1re année avec Free Tier EC2)* | **36,40 $ / mois** | **Full Serverless** (ou **Hybride 1 EC2** la 1re année grâce aux 750h Free Tier). Évite de payer un serveur allumé 24h/24 quand le trafic est quasi nul. |
| **Palier 2 : PME en croissance**<br>*(5 000 à 50 000 clients)* | 5 000 à 50 000 | 100 000 à 1,5 M | **1,50 $ à 3,80 $ / mois**<br>*(Tout le calcul PDF tient encore dans les 400k Go-s Always Free)* | **9,60 $ / mois** | **37,20 $ / mois** | **Full Serverless + Worker EC2 Spot ponctuel**. Le Front-End Serverless reste moins cher qu'un ALB tant que le trafic d'API est < 10M de requêtes. |
| **Palier 3 : E-Commerce Établi**<br>*(50 000 à 300 000 clients)* | 50 000 à 300 000 | 1,5 M à 15 M | **22,00 $ à 48,00 $ / mois**<br>*(Dépassement du Free Tier Lambda PDF + Cognito MAU + API Gateway)* | **12,50 $ / mois** *(1 EC2 t3.small)* | **41,50 $ / mois** | **Bascule vers l'Architecture Hybride !** Au-delà de **~266 000 commandes/mois**, le quota gratuit Lambda est épuisé et le **Worker EC2 Spot (-75 %)** devient beaucoup plus rentable que Lambda pour générer les PDF. |
| **Palier 4 : Grande Échelle / Black Friday**<br>*(> 1 000 000 clients)* | > 1 000 000 | > 50 M | **145,00 $ à 310,00 $ / mois**<br>*(Explosion des coûts API Gateway à 1$/M et Lambda au Go-s + blocage timeout 15 min)* | *Saturé* | **65,00 $ à 95,00 $ / mois**<br>*(ALB + ASG 2 à 4 EC2 + Batch EC2 Spot)* | **Architecture Hybride HA (ALB + ASG EC2 + Batch EC2 Spot)** : Jusqu'à **3 fois moins chère** que le Full Serverless à fort trafic, car un ALB + EC2 absorbe des dizaines de millions de requêtes sans facturation à l'appel API, et l'EC2 Spot traite les millions de PDF sans limite de 15 minutes. |

---

### Conclusion 

1. **Pendant la 1re année (et pour notre démonstration) :** Notre architecture **Hybride (1 EC2 `t3.micro` + Lambda + SQS/SNS + Batch EC2 Spot éphémère)** nous coûte **exactement 0,00 $** (prouvé par AWS Cost Explorer), tout en démontrant la maîtrise complète de l'IaaS (EC2 On-Demand, EC2 Spot, Auto Scaling, ALB) et du PaaS/Serverless (Lambda, DynamoDB, SQS, SNS, S3, Cognito).
2. **En production réelle (hors Free Tier 12 mois) :**
   * **Sous 50 000 clients/mois :** Une approche **Full Serverless** est imbattable financièrement (**< 4 $/mois**), car l'offre *Always Free* permanente de Lambda (400 000 Go-s) et DynamoDB (25 RCU/WCU) absorbe 100 % du trafic sans aucun coût fixe de serveur allumé la nuit.
   * **Dès que les traitements batch s'alourdissent (> 44 000 commandes/mois hors Free Tier, ou > 266 000 commandes/mois avec Free Tier, ou batch > 15 minutes) :** Le **Worker Batch EC2 Spot éphémère (`0,0040 $/h`)** avec auto-destruction (`terminate`) s'impose en réduisant de **75 % à 90 %** la facture de calcul des PDF.
   * **À fort trafic (> 300 000 à 1 000 000 de clients/mois) :** L'architecture **Hybride complète (ALB + Auto Scaling EC2 + Worker EC2 Spot)** devient globalement plus économique que le Full Serverless, car la facturation à la requête d'API Gateway (`1,00 $ / million`) et à la milliseconde de Lambda finit par dépasser le coût fixe plafonné d'un pool d'instances EC2.
