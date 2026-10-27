# Module 02 : Messaging Événementiel (Amazon SNS & Amazon SQS)

Ce dossier configure la couche de messagerie et de découplage asynchrone du projet ([`main.tf`](./main.tf)).

---

## 1. Comment Amazon SNS sait-il à qui envoyer l'e-mail ? (Routage & `FilterPolicy`)

C'est une question d'architecture essentielle à maîtriser pour l'oral :
* **Différence entre Amazon SNS et un serveur SMTP / Amazon SES :**
  * **Amazon SNS (Simple Notification Service)** n'est pas un serveur SMTP ouvert où l'on passe un champ `To: n'importe-qui@gmail.com` sans vérification (ce qui permettrait le spam). SNS est un bus **Pub/Sub** basé sur des **Topics** et des **Abonnements (`Subscriptions`) vérifiés**.
  * Pour recevoir des e-mails d'un Topic SNS, une adresse e-mail doit d'abord être abonnée (`sns:Subscribe`) et l'utilisateur doit cliquer une seule fois sur le lien **« Confirm subscription »** envoyé par AWS (`no-reply@sns.amazonaws.com`).
* **Comment éviter que tous les clients abonnés au Topic reçoivent les commandes des autres ? (`FilterPolicy` + `MessageAttributes`) :**
  * Par défaut dans un Topic Pub/Sub, tous les abonnés reçoivent tous les messages publiés.
  * Pour router chaque e-mail **uniquement vers le client concerné**, notre architecture utilise le mécanisme natif **SNS Message Filtering (`FilterPolicy`)** :
    1. **Lors de l'inscription sur le site (`POST /api/subscribe`) :** Le serveur Front-End abonne l'adresse e-mail du client aux deux Topics SNS en y attachant une règle de filtrage :
       ```json
       {
         "customer_email": ["client@domaine.fr"]
       }
       ```
    2. **Lors de la publication du message (`sns.publish`) par la Lambda ou le Worker Spot :** Le code Python attache l'adresse e-mail de l'acheteur dans les `MessageAttributes` :
       ```python
       sns.publish(
           TopicArn=TOPIC_ARN,
           Subject=f"Confirmation de commande {order_id}",
           Message=...,
           MessageAttributes={
               "customer_email": {
                   "DataType": "String",
                   "StringValue": customer_email
               }
           }
       )
       ```
    3. **Routage par AWS SNS :** Amazon SNS compare `MessageAttributes.customer_email` avec la `FilterPolicy` de chaque abonné et n'envoie l'e-mail **qu'au client correspondant** (ainsi qu'à l'adresse `notification_email` de l'administrateur si elle est configurée sans filtre).

---

## 2. Ce que déploie ce module

1. **Topic SNS `order-confirmation` (Modèle Pub/Sub) :**
   * Déclenché instantanément par la fonction Lambda lorsqu'un client valide une commande.
   * Envoie le premier e-mail de confirmation de réception de commande (expéditeur natif AWS : `no-reply@sns.amazonaws.com`).
2. **Topic SNS `shipping-notification` (Modèle Pub/Sub) :**
   * Déclenché par le Worker EC2 Spot une fois que le colisage (`Colis S/M/L/XL`) est calculé et que la facture PDF est générée.
   * Envoie au client son **numéro de suivi transporteur** (`TRK-EUW3-...`) ainsi que le **lien de téléchargement de sa facture PDF**.
3. **File d'attente SQS `orders-batch-queue` (Modèle File / Tampon) :**
   * Accumule toutes les commandes validées par la Lambda au fil de la journée en attendant le réveil périodique (ou manuel) du Worker EC2 Spot.
   * Conserve les messages jusqu'à **14 jours** (`message_retention_seconds = 1209600`). Même si aucune instance EC2 Spot ne tourne à l'instant T, **aucune commande n'est jamais perdue**.

---

## 3. Pourquoi cette configuration est 100 % Gratuite (AWS Free Tier)

* **Amazon SNS (*Always Free*) :** 1 000 000 de publications gratuites et 1 000 notifications par e-mail gratuites chaque mois.
* **Amazon SQS (*Always Free*) :** 1 000 000 de requêtes gratuites chaque mois.
* **Remplacement FinOps de Kafka MSK :** Un cluster **Amazon MSK (Kafka)** n'a aucune offre Free Tier (~70 $ à 200 $/mois minimum). Le couple **SNS + SQS** remplit exactement ce rôle de bus événementiel et de file de streaming tampon pour **0,00 €**.
