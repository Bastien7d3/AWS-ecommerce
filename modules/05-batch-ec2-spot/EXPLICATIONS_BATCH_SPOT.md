# Module 05 : Worker Batch EC2 Spot (Colisage, Facture PDF & Suivi SNS)

Ce dossier configure la machine virtuelle EC2 Spot dédiée aux traitements lourds asynchrones d'entrepôt ([`main.tf`](./main.tf) et [`src/batch_worker.py.tftpl`](./src/batch_worker.py.tftpl)).

---

## 1. Ce que déploie ce module

1. **Instance EC2 Spot (`t3.micro`, `market_type = "spot"`, disque 8 Go `gp3`) :**
   * Utilise la tarification **Spot** d'AWS (~0,0031 $/heure en `eu-west-3`, soit environ -80 % par rapport au tarif On-Demand).
   * **Aucun port entrant n'est ouvert** dans le Security Group (`spot_worker_sg`) : la machine ne peut pas être attaquée depuis Internet, elle initie uniquement des connexions sortantes vers les API AWS.
2. **Rôle IAM `spot-worker-role` (Moindre privilège) :**
   * Autorise uniquement :
     * `sqs:ReceiveMessage` et `sqs:DeleteMessage` sur la file `orders-batch-queue`.
     * `s3:PutObject` et `s3:GetObject` sur le bucket `invoices`.
     * `dynamodb:UpdateItem` sur la table `orders`.
     * `sns:Publish` sur le Topic `shipping-notification`.
3. **Service Systemd `cloudshop-spot-worker.service` :**
   * Exécute le script [`src/batch_worker.py.tftpl`](./src/batch_worker.py.tftpl) qui écoute la file SQS en continu (*Long Polling*).

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
4. **Notification d'expédition via Amazon SNS :**
   * Publie un message sur le Topic SNS `shipping-notification` contenant le numéro de suivi et un lien pré-signé vers la facture PDF.

---

## 3. Comment personnaliser ce module (Pour le groupe)

* **Ajuster les tailles ou tarifs des cartons transporteur :** Modifiez la liste `CARRIER_BOXES` en haut du fichier [`src/batch_worker.py.tftpl`](./src/batch_worker.py.tftpl).
* **Personnaliser la mise en page de la facture PDF :** Modifiez la fonction `generate_invoice_pdf()` dans [`src/batch_worker.py.tftpl`](./src/batch_worker.py.tftpl).
