# Module 05 : Worker Batch EC2 Spot Éphémère (Colisage & Facturation PDF)

Ce module implémente le composant de traitement par lot lourd d'entrepôt, conçu sur une architecture éphémère à coût réduit (*Scale-to-Zero*) ([`main.tf`](./main.tf) et [`src/batch_worker.py.tftpl`](./src/batch_worker.py.tftpl)).

---

## 1. Principe Architectural : Zéro Instance au Repos (Scale-to-Zero)

Pour les traitements asynchrones non interactifs (génération de documents PDF, calculs d'emballage), maintenir une machine virtuelle 24h/24 est un gaspillage de ressources.

Le module configure un **Launch Template EC2 Spot** (`cloudshop-spot-worker-lt`) associé à un Auto Scaling Group configuré par défaut à **`desired_capacity = 0`**. L'instance n'est créée qu'en cas de travail à effectuer :

1. **Déclenchement Périodique Automatique (`aws_autoscaling_schedule`) :**
   * Chaque nuit à **02h00 UTC** (`0 2 * * *`), l'Auto Scaling Group instancie temporairement un worker Spot pour traiter les commandes accumulées dans SQS durant la journée.
2. **Déclenchement Manuel à la Demande (`POST /api/launch-spot`) :**
   * L'administrateur peut à tout moment déclencher le traitement depuis l'interface web pour vider la file immédiatement.

### Cycle de Vie & Auto-Destruction (`terminate`)
```
[Création Instance Spot] ──► Dépilement en boucle de SQS
                                      │
                         (File SQS entièrement vide)
                                      ▼
                               shutdown -h now
                                      ▼
                        AWS détruit l'instance & l'EBS
                         (Retour strict à 0,00 €/h)
```
Le paramètre `instance_initiated_shutdown_behavior = "terminate"` combiné à `delete_on_termination = true` sur le disque EBS garantit que dès l'arrêt du script Python, **AWS détruit l'intégralité des ressources de calcul et de stockage**, éliminant tout coût résiduel.

---

## 2. Traitements Métier Réalisés par le Worker

À chaque message consommé dans la file SQS, le script Python exécute :

1. **Calcul du Format de Carton Transporteur :**
   * Calcule le volume cumulé des articles avec **+15 % de marge de calage** et le poids total.
   * Sélectionne automatiquement le carton le plus compact et économique :
     * `Colis S` (20 × 15 × 10 cm, max 2 kg) — 4,90 € HT
     * `Colis M` (40 × 30 × 20 cm, max 10 kg) — 8,90 € HT
     * `Colis L` (60 × 40 × 40 cm, max 25 kg) — 14,90 € HT
     * `Colis XL` (100 × 60 × 60 cm, max 100 kg) — 29,90 € HT
2. **Génération de la Facture PDF (`fpdf2`) & Dépôt S3 :**
   * Génère la facture normalisée avec récapitulatif fiscal, dimensions du colis et identifiant d'instance Spot, puis la dépose dans le bucket S3 sous `invoices/facture_<order_id>.pdf`.
3. **Mise à Jour Transactionnelle DynamoDB :**
   * Passe le statut à `SHIPPED`, enregistre le numéro de suivi transporteur (`TRK-EUW3-...`), le taux de remplissage et la clé S3 du PDF.
4. **Notification d'Expédition Ciblée (Amazon SNS) :**
   * Émet la notification sur le topic SNS avec l'attribut `customer_email`, incluant le numéro de suivi et le lien direct vers la facture.

---

## 3. Justification FinOps

* **Tarification Spot en `eu-west-3` :** Le tarif Spot d'une instance `t3.micro` est d'environ **0,0040 $/h** (contre 0,0118 $/h en On-Demand, soit **-66 % de réduction**).
* **Économie du stockage éphémère :** Grâce à l'auto-destruction du volume EBS de 8 Go à chaque cycle, le stockage n'est facturé que pour les minutes d'exécution effectives (soit environ **0,30 $/mois** pour un traitement quotidien de 2 heures, contre 0,70 $/mois si le disque restait provisionné en permanence).
* **Dépassement des limites de Lambda :** Contrairement à une fonction Lambda plafonnée à **15 minutes d'exécution maximum**, le Worker Spot peut traiter un volume arbitrairement grand sans risque de rupture d'exécution.
