# Analyse FinOps & Coûts Réels AWS — Projet CloudShop (FISA 2026)

> **Compte AWS audité :** `689505268069` — **Région :** `eu-west-3` (Paris)
> **Facture réelle actuelle (AWS Cost Explorer) :** **0,00 $** (100 % couvert par le Free Tier AWS).

---

## 1. Coût Réel & Tarif de Chaque Module (du plus simple au plus complet)

### Module 00 : Authentification (`modules/00-auth-cognito`)
* **Ce qui est déployé :** User Pool Cognito (`cloudshop-user-pool`).
* **Notre conso réelle sur AWS :** **2 utilisateurs inscrits** -> **0,00 $**.
* **Tarif AWS :**
  * **Gratuit à vie (*Always Free*) :** jusqu'à **50 000 utilisateurs actifs / mois**.
  * Au-delà : **0,0055 $ par utilisateur actif / mois**.

---

### Module 01 : Base de Données & Stockage (`modules/01-database-dynamodb` + S3)
* **Ce qui est déployé :**
  * 2 tables DynamoDB (`products` et `orders`) en mode **Provisionné (`5 RCU / 5 WCU` chacune = 10 RCU / 10 WCU au total)**.
  * 1 table DynamoDB (`cloudshop-tfstate-locks`) en mode **Pay-Per-Request** (verrouillage Terraform : usage très ponctuel uniquement lors des déploiements).
  * 2 Buckets S3 : `cloudshop-invoices-689505268069` (factures PDF) et `cloudshop-tfstate-fisa2026-unique` (état Terraform).
* **Notre conso réelle sur AWS :**
  * **DynamoDB :** `1 730 opérations` -> **0,00 $**.
  * **Amazon S3 :** **18 fichiers** dans le bucket factures (`82,7 Ko`, ~2,5 Ko par PDF) + **1 fichier** `tfstate` (`128 Ko`) -> **0,00 $** (`0,000002 $`).
* **Tarif AWS :**
  * **DynamoDB (*Always Free*) :** 25 Go + **25 RCU / 25 WCU gratuits à vie** (suffisant pour des millions de lectures/écritures par mois).
  * **Amazon S3 :** **5 Go gratuits** la 1re année, puis **0,024 $ / Go / mois** (100 000 factures PDF de 2,5 Ko = 250 Mo = **0,006 $ / mois**, soit moins d'un centime).

---

### Module 02 : Messaging Événementiel (`modules/02-messaging-sns-sqs`)
* **Ce qui est déployé :** 2 Topics SNS (`order-confirmation`, `shipping-notification`) + 1 File SQS (`orders-batch-queue`, rétention 14 jours).
* **Notre conso réelle sur AWS :**
  * **SQS :** **16 messages envoyés / 16 reçus** (`27 requêtes API`) -> **0,00 $**.
  * **SNS :** **32 publications / 20 e-mails envoyés** -> **0,00 $**.
* **Tarif AWS :**
  * **SQS (*Always Free*) :** **1 000 000 de requêtes / mois gratuites à vie**, puis **0,40 $ / million**.
  * **SNS (*Always Free*) :** **1 000 e-mails / mois gratuits à vie**, puis **2,00 $ pour 100 000 e-mails** (`0,00002 $ / e-mail`).

---

### Module 03 : Prise de Commande Serverless (`modules/03-serverless-lambda`)
* **Ce qui est déployé :** Fonction Lambda `cloudshop-create-order` (`python3.12`, **128 Mo de RAM**, timeout `15 s`).
* **Notre conso réelle sur AWS :**
  * **16 exécutions**, durée moyenne réelle mesurée : **603 ms** (`0,6 s`) -> **0,00 $**.
* **Tarif AWS :**
  * **Lambda (*Always Free*) :** **1 000 000 de requêtes / mois** + **400 000 Go-secondes / mois** gratuits à vie.
  * À `128 Mo` et `0,6 s`, notre Lambda est **100 % gratuite jusqu'à 1 000 000 de commandes / mois**.
  * Au-delà d'un million de commandes : **~1,45 $ par million de commandes**.

---

### Module 04 : Serveur Web Front-End EC2 (`modules/04-frontend-ec2`)
* **Ce qui est déployé :**
  * **Mode Standard (`enable_autoscaling_alb = false`) :** 1 instance EC2 `t3.micro` + 1 disque EBS `gp3` de `8 Go`.
  * **Mode Haute Disponibilité (`enable_autoscaling_alb = true`) :** 1 Load Balancer (ALB) + Auto Scaling Group (`2 à 4 instances EC2 t3.micro`).
* **Notre conso réelle sur AWS :**
  * 1 instance `t3.micro` active (`i-0f3c0b44fd4864ad4`) + 1 disque `8 Go gp3` -> **0,00 $** (couvert par les 750h/mois EC2 et 30 Go EBS gratuits la 1re année).
* **Tarif AWS (hors 1re année gratuite) :**
  * **Mode 1 EC2 `t3.micro` seule :** `8,61 $/mois` (EC2 à `0,0118 $/h` x 730h) + `0,70 $/mois` (disque 8 Go) = **9,31 $ / mois fixes**.
  * **Mode Haute Disponibilité (ALB + 2 EC2 `t3.micro`) :** `17,74 $/mois` (ALB) + `2 x 9,31 $` (2 EC2) = **36,36 $ / mois fixes**.

---

### Module 05 : Worker Batch EC2 Spot Éphémère (`modules/05-batch-ec2-spot`)
* **Ce qui est déployé :** Launch Template EC2 Spot `t3.micro` (`0 instance` allumée au repos). L'instance est créée à la demande (ou à 02h00 la nuit), vide la file SQS, génère les factures PDF, puis **se détruit intégralement avec son disque EBS (`shutdown -h now` -> `terminated`)**.
* **Notre conso réelle sur AWS :**
  * 2 exécutions Spot éphémères (`i-02de293ce918a7d5c`, `i-08694ab1be81f42b5`) -> **0,00 $**.
* **Tarif Spot réel relevé en direct sur AWS `eu-west-3` (Paris) :**
  * **EC2 `t3.micro` Spot :** **0,0040 $ / heure** en `eu-west-3c` (contre `0,0118 $/h` en On-Demand, soit **-66 % de réduction**).
  * **Coût pour 2h de batch par nuit (60h / mois) :**
    * Calcul Spot (`60 h x 0,0040 $/h`) = **0,24 $ / mois**
    * Disque EBS 8 Go pendant ces 60h seulement (`60h / 730h x 0,70 $`) = **0,06 $ / mois**
    * **Coût total du Worker Batch Spot = 0,30 $ / mois !**

---

## 2. Comparaison Simple : Notre Architecture Hybride vs Full Serverless

Pourquoi avons-nous choisi une **architecture hybride** plutôt que du **100 % Serverless** ?
Pour répondre clairement, il suffit de comparer les **2 seules briques qui changent** :
1. **Le Back-Office (Génération des Factures PDF)** : *Worker EC2 Spot* vs *Fonction Lambda*.
2. **Le Front-End (Site Web)** : *Serveur EC2* vs *S3 + CloudFront + API Gateway*.

*(Les briques Cognito, DynamoDB, SQS, SNS et S3 sont identiques dans les deux architectures).*

---

### A. Comparaison n°1 : Générer les Factures PDF (EC2 Spot vs Lambda)

* **Option Full Serverless (une 2e fonction Lambda qui génère le PDF) :**
  * Générer un PDF lourd demande **512 Mo de RAM pendant 3 secondes** (`1,5 Go-seconde` par facture).
  * **Prix catalogue d'une facture PDF sur Lambda :** **0,000025 $ par commande** (soit **2,50 $ pour 100 000 commandes**).
  * **Limite technique majeure :** Lambda plante au bout de **15 minutes maximum** (impossible de faire un gros traitement comptable de fin de journée en une seule fois).
* **Notre Option (Worker EC2 Spot Éphémère à 0,30 $ / mois pour 2h/nuit) :**
  * L'instance Spot `t3.micro` déjà démarrée génère les PDF à la chaîne sans temps de démarrage (*cold start*) pour **0,30 $ / mois** (base 2h/nuit).
* **Verdict & Chiffre Clé à retenir :**
  * **Comparaison sur le tarif catalogue (hors quota gratuit) :**
    * `0,30 $ / 0,000025 $` = **12 000 commandes / mois** (~400 commandes / jour).
    * **Dès 12 000 commandes/mois**, le Worker EC2 Spot (`0,30 $/mois`) coûte moins cher que Lambda.
  * **Comparaison en comptant le cadeau mensuel gratuit d'AWS Lambda (*Always Free* : 400 000 Go-s/mois) :**
    * Le quota gratuit de Lambda permet de générer gratuitement jusqu'à `400 000 / 1,5` = **266 000 factures PDF / mois**.
    * Au-delà de **266 000 commandes / mois** (ou dès que le lot dépasse **15 minutes**), le Worker EC2 Spot s'impose dans tous les cas.

---

### B. Comparaison n°2 : Héberger le Site Web Front-End (EC2 vs S3 + API Gateway)

*(Hypothèse simple : 1 client visite le site = 20 clics/appels API et 1 commande)*

* **Option Full Serverless (Site statique S3 + CloudFront + API Gateway) :**
  * **0,00 $ de coût fixe** quand il n'y a aucun visiteur.
  * Facturé au clic : environ **0,05 $ pour 1 000 clients** (API Gateway coûte `1,00 $ par million de requêtes` + trafic CloudFront).
* **Notre Option (Front-End sur EC2) :**
  * **1re année :** **0,00 $ / mois** (couvert par les 750h/mois du Free Tier EC2).
  * **Après la 1re année :**
    * **1 EC2 `t3.micro` seule :** Coût fixe de **9,31 $ / mois**, peu importe qu'il y ait 100 ou 150 000 clients.
    * **Haute Disponibilité (Load Balancer ALB + 2 EC2) :** Coût fixe de **36,36 $ / mois**.

---

### C. Tableau Récapitulatif Simple : Quelle solution est la plus rentable selon le nombre de clients ?

*(Coûts mensuels totaux après la 1re année, incluant les quotas gratuits à vie Always Free)*

| Nombre de Clients / Mois (= Commandes / Mois) | Architecture **Full Serverless** (API Gateway + 2 Lambdas) | Notre Architecture **Hybride Simple** (1 EC2 Front + Lambda + Spot) | Notre Architecture **Hybride Haute Dispo** (ALB + 2 EC2 + Lambda + Spot) | Quelle est la solution la plus judicieuse financièrement ? |
| :--- | :--- | :--- | :--- | :--- |
| **1. Petit trafic**<br>**0 à 10 000 clients / mois** | **~0,50 $ / mois** | **9,60 $ / mois**<br>*(0,00 $ la 1re année)* | **36,60 $ / mois** | **Full Serverless** (ou **Hybride 1 EC2 pendant la 1re année gratuite**). Inutile de payer une machine EC2 à 9,31 $/mois s'il y a très peu de clients. |
| **2. Trafic moyen**<br>**10 000 à 200 000 clients / mois** | **1,00 $ à 12,00 $ / mois** | **9,60 $ / mois** | **37,00 $ / mois** | **Égalité (~10 $/mois)** vers **180 000 clients/mois** : le coût des clics sur API Gateway + CloudFront rattrape le prix fixe d'une petite instance EC2 (`9,31 $`). |
| **3. Fort trafic**<br>**300 000 clients / mois** | **~28,00 $ / mois**<br>*(Quota gratuit Lambda PDF dépassé + API Gateway)* | **~13,00 $ / mois** | **~39,00 $ / mois** | **Architecture Hybride !** À partir de **266 000 commandes/mois**, Lambda devient payante pour les PDF alors que le Worker EC2 Spot ne coûte que **0,30 $/mois**. |
| **4. Très fort trafic**<br>**1 000 000 clients / mois** | **~135,00 $ / mois**<br>*(API Gateway + Lambda PDF explosent + blocage des 15 min)* | *1 seule EC2 ne suffit plus* | **~55,00 $ / mois**<br>*(ALB + Auto Scaling 2 à 4 EC2 + Spot)* | **Architecture Hybride Haute Dispo (ALB + ASG + Spot)** : **2,5 fois moins chère** que le Full Serverless, car le coût des serveurs EC2 est plafonné alors que le Serverless facture chaque million de requêtes plein pot. |

---

### Résumé en 3 Phrases pour la Soutenance

1. **Aujourd'hui (Année 1 / Démo) :** Notre architecture Hybride coûte **0,00 $** sur AWS grâce au Free Tier (750h EC2 + Always Free Lambda/DynamoDB/SQS/SNS/Cognito).
2. **Pour la génération des factures PDF (Batch) :** Le Worker EC2 Spot auto-destructeur ne coûte que **0,30 $/mois** (pour 2h/nuit à `0,0040 $/h`). Il est plus rentable que Lambda dès **12 000 commandes/mois** en tarif brut (et dès **266 000 commandes/mois** en comptant le quota gratuit Lambda), tout en faisant sauter la limite des **15 minutes** de Lambda.
3. **Pour le site Front-End :** Le **Full Serverless** est plus économique pour démarrer à petit trafic (**< 180 000 clients/mois** hors Free Tier), tandis que notre architecture **EC2 + Load Balancer + Auto Scaling** devient **2 à 3 fois moins chère** à grande échelle (**> 300 000 à 1 000 000 de clients/mois**).
