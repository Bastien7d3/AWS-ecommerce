# Guide de Réunion & Pitch pour le Groupe — Projet AWS FISA 2026

**Date de préparation :** 26 octobre 2026  
**Auteur :** Bastien  
**Objectif de la réunion :** Aligner le groupe sur l'architecture retenue, valider l'analyse des coûts (Free Tier), montrer le PoC déjà fonctionnel (EC2 Spot + Facture PDF) et se répartir le travail.

---

## 1. Le Pitch en 2 Minutes (Ce qu'il faut dire au groupe)

1. **Ce que demande le prof (Pr. Raouf Boulkroune) :**
   * Créer une boutique e-commerce hautement disponible sur AWS avec **Terraform**.
   * Dans le rapport et la soutenance, on doit **présenter et comparer 2 solutions** :
     * **Solution 1 :** 100 % Machines Virtuelles (IaaS).
     * **Solution 2 :** 100 % Serverless.
   * **Mais pour l'implémentation réelle**, le sujet impose d'utiliser **à la fois EC2 (VM) et Serverless (Lambda + SNS)** tout en restant à **0,00 € (AWS Free Tier)**.

2. **Notre idée directrice (Simple, réaliste et ultra-rentable) :**
   * **En journée (Temps réel Client) :**
     * Le site web tourne en Haute Disponibilité derrière un **Application Load Balancer (ALB)** et **2 petites VM EC2 (`t3.micro`)** sur 2 zones de disponibilité.
     * Quand un client commande, une fonction **AWS Lambda** enregistre la commande dans **DynamoDB**, envoie un premier mail de confirmation immédiat via **Amazon SNS**, et dépose la commande dans une file d'attente **Amazon SQS**.
   * **La nuit ou sur seuil d'alerte (Traitement Batch Lourd sur EC2 Spot) :**
     * Au lieu de laisser un serveur de traitement allumé 24h/24, on lance une **instance EC2 Spot (`t3.micro` à -80 %)** uniquement quand c'est nécessaire (la nuit ou quand la file SQS dépasse un seuil).
     * Cette instance EC2 Spot fait le "gros travail" logistique :
       1. Elle **calcule les dimensions et le poids** des articles pour choisir le carton transporteur optimal (**Colis S, M, L ou XL**).
       2. Elle **génère la facture PDF officielle** avec le détail TVA et le code de suivi, et l'archive sur **Amazon S3**.
       3. Elle passe la commande au statut **`SHIPPED` (Expédiée)** dans DynamoDB et envoie un **2ème mail via SNS** au client avec son **numéro de suivi transporteur** et le lien de sa facture PDF !
     * Dès que la file SQS est vide, l'instance Spot s'éteint toute seule (*Scale-to-Zero*).

3. **Le Bonus Surveillance CloudWatch ("Split du Batch en 2") :**
   * On place une alarme **CloudWatch** sur le nombre de commandes dans la file SQS.
   * L'admin Cloud peut régler le seuil dans Terraform : s'il y a un pic inhabituel de commandes (ex : > 50 commandes), CloudWatch lance une **2ème instance EC2 Spot en parallèle** pour couper le batch en 2 et diviser le délai de traitement par deux !

---

## 2. Les 3 Arguments FinOps Clés (Pour convaincre le groupe et le prof)

1. **Pourquoi on n'implémente pas Kafka MSK ou RDS Multi-AZ en vrai ?**
   * Le prof dit dans le sujet : *« Si une solution optimale nécessite un coût qui dépasse le budget, n'hésitez pas à présenter l'architecture sans l'implémenter. »*
   * **Amazon MSK (Kafka)** n'a **aucun Free Tier** (~70 $ à 200 $/mois minimum). On le présente dans le schéma de la Solution 1, et on le remplace dans notre code par **SNS + SQS** (100 % *Always Free*).
   * **Amazon RDS Multi-AZ** double la consommation d'heures (1 488 h/mois > 750 h gratuites). On le remplace par **DynamoDB en mode Provisioned (5 RCU / 5 WCU)** qui est 100 % *Always Free*.

2. **Le calcul du Seuil de Rentabilité (*Break-Even Point*) :**
   * On a calculé le coût exact entre faire la génération PDF sur **Lambda** vs sur **EC2 Spot éphémère (2h par nuit)** :
     * **Coût Lambda :** ~0,0000202 $ par commande (pour 3s à 512 Mo de RAM).
     * **Coût EC2 Spot (2h/nuit = 60h/mois + 8 Go EBS) :** **0,89 $ / mois fixe** !
     * **Seuil de rentabilité :** **44 000 commandes / mois** (~1 450 commandes/jour). En dessous, Lambda est moins chère ; au-dessus (ou si le batch dépasse la limite stricte des 15 minutes d'une Lambda), l'EC2 Spot est imbattable (-75 % à 200 000 commandes).

3. **La preuve que ça marche déjà (PoC dans le dossier `04_POC_TERRAFORM_EC2_SPOT_PDF`) :**
   * Montrer au groupe le fichier **`facture_CMD-2026-001.pdf`** : il a été généré hier sur AWS par une vraie instance EC2 Spot (`i-07945481eb776828e`) déployée par notre Terraform, puis tout a été détruit proprement (`terraform destroy`) pour coûter 0 €.

---

## 3. Proposition de Répartition du Travail (Groupe de 2 ou 3)

| Lot de travail | Contenu Technique (Terraform + Code) | Partie du Rapport / Présentation associée |
| :--- | :--- | :--- |
| **Lot 1 : Front-End HA & Réseau (IaaS)** | • Module Terraform `vpc` & `compute_web`<br>• Application Load Balancer (ALB) + Auto Scaling Group (2 VM `t3.micro` Multi-AZ)<br>• Page Web simple (Catalogue produits, Panier, Suivi de commande) | • Présentation de la **Solution 1 (100 % VM)**<br>• Explication de la Haute Disponibilité Multi-AZ et du Load Balancing |
| **Lot 2 : Cœur Serverless & Données** | • Module Terraform `database` & `serverless_api`<br>• Tables DynamoDB (`Products` & `Orders`)<br>• Fonction Lambda `CreateOrder` + Topic SNS de confirmation de commande | • Présentation de la **Solution 2 (100 % Serverless)**<br>• Explication de DynamoDB (Provisioned vs On-Demand) et du modèle Pub/Sub SNS |
| **Lot 3 : Batch EC2 Spot, PDF & FinOps** *(Déjà bien avancé avec le PoC !)* | • Module Terraform `compute_spot` & `monitoring`<br>• File SQS + Worker EC2 Spot (`fpdf2`, calcul colis S/M/L/XL, statut `SHIPPED`, SNS N° de suivi)<br>• Alarmes CloudWatch (seuil de déclenchement & split en 2) | • **Analyse FinOps & Seuil de rentabilité** (44 000 cmd/mois)<br>• Justification des choix Free Tier et démonstration de la facture PDF |

---

## 4. Checklist des Décisions à Valider Demain avec le Groupe

- [ ] Valider le découpage en 3 lots (qui prend quel lot ?).
- [ ] Choisir sur quel compte AWS on fait la démo finale le jour de la soutenance (grâce à Terraform, on peut déployer sur n'importe lequel de nos comptes en 2 minutes).
- [ ] Définir les 4 ou 5 produits qu'on met dans le catalogue de la boutique pour la démo.
