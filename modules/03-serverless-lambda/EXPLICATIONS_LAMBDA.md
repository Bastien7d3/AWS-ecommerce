# Module 03 : Cœur Serverless (AWS Lambda — Prise de Commande)

Ce dossier contient la fonction AWS Lambda qui orchestre de manière transactionnelle et sans serveur la validation d'une commande ([`main.tf`](./main.tf) et [`src/create_order.py`](./src/create_order.py)).

---

## 1. Ce que déploie ce module

1. **Rôle IAM `create-order-lambda-role` :**
   * Applique le principe du **moindre privilège** : autorise exclusivement la lecture/mise à jour de la table `products`, l'écriture dans la table `orders`, la publication sur le Topic SNS `order-confirmation` et l'envoi de messages dans la file SQS `orders-batch-queue`.
2. **Archive automatique (`data.archive_file`) :**
   * Compresse automatiquement le fichier Python [`src/create_order.py`](./src/create_order.py) en archive `.zip` à chaque modification du code.
3. **Fonction AWS Lambda (`cloudshop-create-order`) :**
   * Exécutée sous **Python 3.12** avec **128 Mo de RAM**.
   * Reçoit les identifiants des autres modules via ses variables d'environnement (`PRODUCTS_TABLE`, `ORDERS_TABLE`, `SNS_CONFIRM_ARN`, `SQS_BATCH_URL`).

---

## 2. Les 4 Actions Exécutées lors d'une Commande

Lorsqu'un client clique sur "Commander" sur le site Front-End EC2, cette Lambda exécute séquentiellement :
1. **Vérification & Décrémentation du Stock :** Lit l'article dans la table DynamoDB `products` et décrémente atomiquement le stock (`stock = stock - qty`).
2. **Enregistrement de la Commande (Audit initial) :** Crée l'entrée dans la table DynamoDB `orders` avec un identifiant unique (`CMD-2026-...`) et le statut initial `PENDING`.
3. **Notification Temps Réel (SNS) :** Publie un message de confirmation immédiate sur le Topic SNS `order-confirmation`.
4. **Mise en File d'Attente (SQS) :** Pousse les détails de la commande (articles, dimensions, poids) dans la file SQS `orders-batch-queue` pour le traitement différé par l'instance EC2 Spot.

---

## 3. Pourquoi cette configuration est 100 % Gratuite (AWS Free Tier)

* **AWS Lambda (*Always Free*) :** 1 000 000 de requêtes et 400 000 Go-secondes de calcul sont gratuits chaque mois sans limite de temps.
* Lorsqu'aucun client ne passe commande, la fonction Lambda ne tourne pas et coûte **strictement 0,00 €**.

---

## 4. Comment personnaliser ce module (Pour le groupe)

* **Modifier la logique métier d'une commande :** Éditez simplement le fichier [`src/create_order.py`](./src/create_order.py) (par exemple pour gérer un code promo, plusieurs articles dans un panier ou des champs clients supplémentaires), puis relancez `terraform apply` : Terraform détectera le changement de hash SHA-256 et mettra à jour la Lambda en 3 secondes.
