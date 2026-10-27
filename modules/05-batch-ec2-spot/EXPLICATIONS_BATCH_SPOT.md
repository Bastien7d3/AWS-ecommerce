# Module 05 : Worker Batch EC2 Spot Éphémère (Périodique, Manuel & Auto-Destructeur)

Ce dossier configure le **Launch Template EC2 Spot** et le **groupe Auto Scaling planifié** dédiés aux traitements lourds asynchrones d'entrepôt ([`main.tf`](./main.tf) et [`src/batch_worker.py.tftpl`](./src/batch_worker.py.tftpl)).

---

## 1. Principe Clé : Zéro Instance au Repos (Exécution Périodique ou à la Demande)

Contrairement au serveur Front-End qui reste allumé pour recevoir les visiteurs, **aucune instance EC2 Spot ne tourne en permanence au repos (`desired_capacity = 0`)**.

Une instance EC2 Spot (`t3.micro`, `market_type = "spot"`) est créée dynamiquement à partir du Launch Template (`cloudshop-spot-worker-lt`) dans **deux cas** :
1. **Lancement Périodique Automatique (`aws_autoscaling_schedule`) :**
   * Chaque nuit à **02h00 UTC** (`recurrence = "0 2 * * *"`), l'Auto Scaling Group passe `desired_capacity = 1` pour créer une instance Spot et vider toutes les commandes de la journée accumulées dans SQS.
2. **Lancement Manuel à la Demande par l'Admin (`ec2:RunInstances`) :**
   * Depuis le bouton **« 🚀 Créer & Lancer une Instance EC2 Spot maintenant »** sur l'interface web (ou via AWS CLI), l'administrateur instancie immédiatement un worker EC2 Spot à partir du Launch Template.

### Cycle de vie complet et Auto-Destruction (`terminate`)
1. L'instance EC2 Spot démarre et exécute automatiquement [`src/batch_worker.py.tftpl`](./src/batch_worker.py.tftpl) via `user_data`.
2. Elle dépile en boucle tous les messages en attente dans la file **Amazon SQS** (`orders-batch-queue`).
3. Pour chaque commande, elle calcule le carton optimal (`Colis S/M/L/XL`), génère la **Facture PDF** avec `fpdf2`, l'uploade sur **Amazon S3**, met à jour **DynamoDB** (`SHIPPED`) et notifie **Amazon SNS**.
4. Dès que la file SQS est vide (2 sondages consécutifs sans message), le script Python exécute `shutdown -h now`.
5. Grâce au paramètre `instance_initiated_shutdown_behavior = "terminate"` configuré dans le Launch Template, **AWS détruit intégralement l'instance EC2 Spot et son disque EBS dès qu'elle s'éteint**. La facturation retombe immédiatement à **0,00 €/h**.

---

## 2. Les 4 Opérations Réalisées pour Chaque Commande

1. **Calcul du format de carton transporteur (`S`, `M`, `L`, `XL`) :**
   * Calcule le volume total des articles commandés avec **+15 % de marge de calage** et le poids total.
   * Sélectionne automatiquement le plus petit carton compatible parmi :
     * `Colis S (20x15x10 cm, max 2 kg)` — 4,90 € HT
     * `Colis M (40x30x20 cm, max 10 kg)` — 8,90 € HT
     * `Colis L (60x40x40 cm, max 25 kg)` — 14,90 € HT
     * `Colis XL (100x60x60 cm, max 100 kg)` — 29,90 € HT
2. **Génération de la Facture PDF officielle (`fpdf2`) & Upload S3 :**
   * Crée la facture PDF complète (voir [`facture_CMD-2026-001.pdf`](./facture_CMD-2026-001.pdf)) et l'envoie dans `s3://<bucket>/invoices/facture_<order_id>.pdf`.
3. **Mise à jour de la commande dans DynamoDB (`SHIPPED`) :**
   * Enregistre le statut `SHIPPED`, le numéro de suivi `TRK-EUW3-...`, le carton choisi, le taux de remplissage et la clé S3 du PDF.
4. **Notification d'expédition ciblée via Amazon SNS :**
   * Publie un message sur le Topic SNS `shipping-notification` avec l'attribut `MessageAttributes.customer_email` pour que seul le client concerné (et l'admin) reçoive le suivi et le lien pré-signé vers la facture PDF.

---

## 3. Comment personnaliser ce module (Pour le groupe)

* **Modifier l'horaire du batch périodique :** Changez l'expression Cron `recurrence = "0 2 * * *"` dans [`main.tf`](./main.tf).
* **Ajuster les tailles ou tarifs des cartons transporteur :** Modifiez la liste `CARRIER_BOXES` en haut du fichier [`src/batch_worker.py.tftpl`](./src/batch_worker.py.tftpl).
* **Personnaliser la mise en page de la facture PDF :** Modifiez la fonction `generate_invoice_pdf()` dans [`src/batch_worker.py.tftpl`](./src/batch_worker.py.tftpl).
