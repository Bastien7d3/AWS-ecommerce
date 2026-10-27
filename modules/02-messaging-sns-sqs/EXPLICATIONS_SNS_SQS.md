# Module 02 : Messaging Événementiel (Amazon SNS & Amazon SQS)

Ce dossier configure la couche de messagerie et de découplage asynchrone du projet ([`main.tf`](./main.tf)).

---

## 1. Ce que déploie ce module

1. **Topic SNS `order-confirmation` (Modèle Pub/Sub) :**
   * Déclenché instantanément par la fonction Lambda lorsqu'un client valide une commande.
   * Envoie le premier e-mail de confirmation de réception de commande (expéditeur natif AWS : `no-reply@sns.amazonaws.com`).
2. **Topic SNS `shipping-notification` (Modèle Pub/Sub) :**
   * Déclenché par le Worker EC2 Spot une fois que le colisage (`Colis S/M/L/XL`) est calculé et que la facture PDF est générée.
   * Envoie au client son **numéro de suivi transporteur** (`TRK-EUW3-...`) ainsi que le **lien de téléchargement de sa facture PDF**.
3. **File d'attente SQS `orders-batch-queue` (Modèle File / Tampon) :**
   * Accumule toutes les commandes validées par la Lambda au fil de la journée.
   * Conserve les messages jusqu'à **14 jours** (`message_retention_seconds = 1209600`). Même si l'instance EC2 Spot est éteinte ou interrompue par AWS, **aucune commande n'est jamais perdue**.

---

## 2. Pourquoi cette configuration est 100 % Gratuite (AWS Free Tier)

* **Amazon SNS (*Always Free*) :** 1 000 000 de publications gratuites et 1 000 notifications par e-mail gratuites chaque mois.
* **Amazon SQS (*Always Free*) :** 1 000 000 de requêtes gratuites chaque mois.
* **Remplacement FinOps de Kafka MSK :** Dans le rapport, nous expliquons qu'un cluster **Amazon MSK (Kafka)** n'a aucune offre Free Tier (~70 $ à 200 $/mois minimum). Le couple **SNS + SQS** remplit exactement ce rôle de bus événementiel et de file de streaming tampon pour **0,00 €**.

---

## 3. Comment ce module est connecté aux autres

* **Depuis `03-serverless-lambda` :** La Lambda publie dans `order-confirmation` (SNS) et envoie le JSON de la commande dans `orders-batch-queue` (SQS).
* **Vers `05-batch-ec2-spot` :** L'instance EC2 Spot dépile les messages de `orders-batch-queue` (SQS) et publie la confirmation finale dans `shipping-notification` (SNS).

---

## 4. Comment personnaliser ce module (Pour le groupe)

* **Recevoir les vrais e-mails lors de la démo :** Renseignez la variable `notification_email` dans le fichier `variables.tf` à la racine du projet (ex : `default = "votre.email@domaine.fr"`), puis cliquez sur le lien `"Confirm subscription"` reçu dans votre boîte mail lors du `terraform apply`.
