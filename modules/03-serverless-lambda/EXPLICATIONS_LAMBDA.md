# Module 03 : Cœur Serverless (AWS Lambda — Prise de Commande)

Ce module gère le traitement transactionnel des commandes sans serveur via une fonction AWS Lambda dédiée ([`main.tf`](./main.tf) et [`src/create_order.py`](./src/create_order.py)).

---

## 1. Composants Déployés

1. **Rôle IAM `create-order-lambda-role` (Moindre Privilège) :**
   * Autorise strictement les opérations nécessaires : lecture/écriture sur les tables DynamoDB `products` et `orders`, publication sur le Topic SNS `order-confirmation`, et écriture sur la file SQS `orders-batch-queue`.
2. **Packaging Automatisé (`archive_file`) :**
   * Package automatiquement le code source Python [`src/create_order.py`](./src/create_order.py) dans un fichier `.zip` lors du `terraform apply`.
3. **Fonction AWS Lambda (`cloudshop-create-order`) :**
   * Environnement d'exécution : **Python 3.12**.
   * Configuration mémoire : **128 Mo de RAM**, timeout de **15 secondes**.
   * Reçoit les ARN et noms de ressources dynamiquement par variables d'environnement Terraform.

---

## 2. Déroulement Transactionnel d'une Commande

À chaque validation de commande envoyée par le serveur Front-End, la fonction exécute séquentiellement :

```
[Requête Client]
       │
       ▼
 1. Décrémentation atomique du stock (DynamoDB 'products')
       │  (ConditionExpression : stock >= quantité demandée)
       ▼
 2. Création de la commande avec statut 'PENDING' (DynamoDB 'orders')
       │
       ▼
 3. Publication de la notification d'accusé de réception (Amazon SNS)
       │
       ▼
 4. Injection du message complet dans la file de batch (Amazon SQS)
```

L'opération est atomique : en cas de rupture de stock, la transaction échoue immédiatement sans modifier la base ni émettre de message.

---

## 3. Justification FinOps

* **Facturation au millième de seconde :** La fonction ne consomme aucune ressource au repos (coût nul en l'absence de commande).
* **Consommation mesurée sur AWS :** L'exécution moyenne prend **603 ms** pour **128 Mo de RAM**, soit `0,075 Go-seconde` par commande.
* **Couverture Free Tier :** L'allocation *Always Free* d'AWS allouant **400 000 Go-secondes** et **1 000 000 de requêtes par mois**, le service reste à **0,00 €** jusqu'à un million de commandes mensuelles.
