# Module 02 : Messaging Événementiel (Amazon SNS & Amazon SQS)

Ce module implémente le bus d'événements et la file tampon garantissant le découplage asynchrone entre la prise de commande et le traitement d'entrepôt ([`main.tf`](./main.tf)).

---

## 1. Composants Déployés

1. **Topic SNS `order-confirmation` (Notifications Client Ciblées) :**
   * Canal principal auquel chaque client s'abonne lors de son inscription (un seul clic de confirmation *Confirm subscription* requis côté client).
   * Publié instantanément par la fonction Lambda dès la validation du panier (statut `PENDING`), puis par le Worker Batch EC2 Spot lors de l'expédition (`SHIPPED` + numéro de suivi `TRK-EUW3-...` + lien direct vers la facture PDF).
2. **Topic SNS `shipping-notification` (Canal Logistique Dédié) :**
   * Topic additionnel disponible pour dissocier les flux logistiques/supervision des notifications d'achat.
3. **File d'Attente SQS `orders-batch-queue` (Tampon Asynchrone) :**
   * File standard avec rétention de **14 jours** (`1 209 600 s`) et délai de visibilité de **120 secondes**.
   * Découple entièrement la prise de commande du traitement batch : même si le Worker Spot est éteint ou interrompu par AWS, aucun message n'est perdu.

---

## 2. Mécanisme de Routage E-mail Client (FilterPolicy)

Dans un système Pub/Sub standard, tous les abonnés d'un topic reçoivent l'ensemble des messages. Pour garantir la confidentialité sans déployer de serveur SMTP ouvert, l'architecture utilise le filtrage natif SNS :

1. **Souscription avec filtre :** Lors de l'enregistrement de l'e-mail du client, l'abonnement SNS est créé avec un attribut de filtrage :
   ```json
   { "customer_email": ["client@domaine.fr"] }
   ```
2. **Attribution des messages :** Chaque publication (par Lambda ou par le Worker Spot) inclut l'e-mail du client dans les métadonnées :
   ```python
   MessageAttributes = {
       "customer_email": {"DataType": "String", "StringValue": customer_email}
   }
   ```
3. **Distribution ciblée :** Amazon SNS évalue la règle côté AWS et ne délivre l'e-mail qu'au destinataire légitime.

---

## 3. Justification FinOps

* **Amazon SQS (*Always Free*) :** 1 000 000 de requêtes par mois gratuites à vie (le projet en consomme moins d'une centaine en phase de test).
* **Amazon SNS (*Always Free*) :** 1 000 000 de publications et 1 000 e-mails par mois gratuits à vie.
* **Alternative économique à Kafka (Amazon MSK) :** Amazon MSK nécessite au minimum 2 brokers managés (~70 $ à 150 $/mois, sans offre gratuite). Le couple SNS + SQS remplit le rôle d'ingestion et de streaming tampon avec une tolérance aux pannes équivalente pour **0,00 €**.
