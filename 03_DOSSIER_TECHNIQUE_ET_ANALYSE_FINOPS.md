# Dossier Technique d'Architecture & Analyse FinOps Approfondie

**Projet :** Déploiement Boutique E-Commerce Haute Disponibilité (AWS Free Tier & Terraform)  
**Contexte :** FISA 2026 — Enseignant : Pr. Raouf Boulkroune  
**Étudiant :** Bastien | **Compte :** `689505268069` (`eu-west-3`)

---

## 1. Vue d'Ensemble de la Solution Hybride & Surveillance Élastique

```mermaid
flowchart TB
    subgraph Front_Tier["1. Entrée & Présentation (Haute Disponibilité Web)"]
        User["Client Web"]
        ALB["Application Load Balancer (Public, Multi-AZ)"]
        subgraph ASG_Web["Auto Scaling Group Web (2 VM)"]
            EC2_Web1["EC2 Web Zone A (t3.micro)"]
            EC2_Web2["EC2 Web Zone B (t3.micro)"]
        end
        User -->|HTTP :80| ALB
        ALB -->|Forward :80| EC2_Web1 & EC2_Web2
    end

    subgraph Serverless_Order["2. Cœur de Commande Transactionnel (Serverless)"]
        Lambda["AWS Lambda: CreateOrder (Python 3.12)"]
        DDB_Catalog[("DynamoDB: Products (Dimensions & Poids)")]
        DDB_Orders[("DynamoDB: Orders (Statuts & Suivi)")]
        SNS(("Amazon SNS: OrderEventsTopic"))
        
        EC2_Web1 & EC2_Web2 -->|POST /order| Lambda
        Lambda -->|Décrémente stock| DDB_Catalog
        Lambda -->|Insère commande (Status: PENDING)| DDB_Orders
        Lambda -->|Mail 1: Confirmation réception| SNS
    end

    subgraph Monitoring_Buffer["3. File Tampon SQS & Surveillance CloudWatch (Seuil Admin)"]
        SQS[["Amazon SQS: batch-fulfillment-queue"]]
        CW["CloudWatch Alarms (ApproximateNumberOfMessagesVisible)"]
        Admin["Admin Cloud (Variables Terraform: seuil_1=10, seuil_split=50)"]
        
        Lambda -->|Empile la commande| SQS
        Admin -.->|Règle les seuils| CW
        SQS -->|Remonte la métrique en continu| CW
    end

    subgraph Async_Spot_Batch["4. Batch Élastique EC2 Spot (0 -> 1 -> 2 VM en cas de pic)"]
        Spot1["EC2 Spot Worker #1 (t3.micro Spot)"]
        Spot2["EC2 Spot Worker #2 (Split du batch si pic !)"]
        S3_Bucket[("Amazon S3: Factures PDF & Audit")]
        
        CW -->|Seuil normal (ou 02h00)| Spot1
        CW -->|Pic de charge (> seuil_split)| Spot2
        SQS -->|Distribution parallèle (Visibility Timeout)| Spot1 & Spot2
        Spot1 & Spot2 -->|1. Calcul Colis (S/M/L/XL) + N° Suivi| DDB_Orders
        Spot1 & Spot2 -->|2. Génère Facture PDF| S3_Bucket
        Spot1 & Spot2 -->|3. Mail 2: Expédié + N° Suivi + Lien PDF| SNS
    end
```

---

## 2. Détail du Traitement Batch sur EC2 Spot & Notification SNS

### 2.1 Calcul de Dimensionnement du Colis (*Carrier Box Sizing*)
Chaque produit du catalogue possède ses dimensions $(L \times l \times h\text{ en cm})$ et son poids unitaire $(\text{kg})$. Le Worker EC2 Spot calcule le volume total cumulé (avec une marge de calage de 15 %) et le poids total de la commande, puis choisit parmi les **4 formats de cartons prédéfinis du transporteur** :

| Format Transporteur | Dimensions Max $(L \times l \times h)$ | Volume Utile | Poids Max | Coût Transporteur |
| :--- | :---: | :---: | :---: | :---: |
| **Colis S (Small)** | $20 \times 15 \times 10\text{ cm}$ | $3\,000\text{ cm}^3$ | $2,0\text{ kg}$ | $4,90\text{ €}$ |
| **Colis M (Medium)** | $40 \times 30 \times 20\text{ cm}$ | $24\,000\text{ cm}^3$ | $10,0\text{ kg}$ | $8,90\text{ €}$ |
| **Colis L (Large)** | $60 \times 40 \times 40\text{ cm}$ | $96\,000\text{ cm}^3$ | $25,0\text{ kg}$ | $14,90\text{ €}$ |
| **Colis XL (Palette)** | $100 \times 60 \times 60\text{ cm}$ | $360\,000\text{ cm}^3$ | $100,0\text{ kg}$ | $29,90\text{ €}$ |

### 2.2 Génération de la Facture PDF & Mise à Jour du Statut
Une fois le carton déterminé :
1. Le worker attribue un **numéro de suivi transporteur unique** (ex : `TRK-EUW3-2026-84920`).
2. Il génère une **facture PDF complète** (`fpdf2`) intégrant :
   * Les coordonnées client et références de la commande,
   * Le détail des lignes produits (quantité, dimensions, poids, prix HT/TVA/TTC),
   * L'encadré logistique (**Format de carton sélectionné**, poids total, taux de remplissage volumétrique, **N° de suivi**).
3. Il dépose le PDF sur **Amazon S3** et génère une URL signée (*Presigned URL*) valide 7 jours.
4. Il met à jour la commande dans **DynamoDB** :
   $$\text{PENDING} \longrightarrow \text{PACKAGED} \longrightarrow \text{SHIPPED}$$
5. Il publie dans **Amazon SNS** un message d'expédition contenant le **numéro de suivi** et le **lien de téléchargement de la facture PDF**, envoyé par e-mail au client.

---

## 3. Surveillance CloudWatch & "Split" du Batch en Cas de Pic

Pour éviter qu'un afflux soudain de commandes ne retarde les expéditions, l'administrateur Cloud dispose d'un système de surveillance basé sur **Amazon CloudWatch** et **Amazon SQS** :

1. **Métrique surveillée :** `ApproximateNumberOfMessagesVisible` (nombre de commandes en attente dans la file SQS) — **100 % gratuit** (métrique native AWS + jusqu'à 10 alarmes CloudWatch incluses dans l'offre *Always Free*).
2. **Deux seuils réglables par l'Admin Cloud (`variables.tf`) :**
   * **Seuil 1 (`spot_trigger_threshold`, ex : 10 commandes) :** Déclenche l'alarme `sqs-batch-start-alarm` qui passe la capacité de l'Auto Scaling Group Spot de **`0` à `1` instance**.
   * **Seuil 2 (`spot_split_threshold`, ex : 50 commandes) :** S'il y a beaucoup plus de commandes que d'habitude, l'alarme `sqs-batch-split-alarm` passe la capacité à **`2` instances Spot** !
3. **Partage automatique de la charge sans doublon :**
   * Les 2 instances Spot lisent la même file SQS en parallèle.
   * Dès que l'instance #1 récupère un lot de messages, SQS les verrouille temporairement (*Visibility Timeout* de 60s) pour que l'instance #2 prenne le lot suivant. Le batch est ainsi **divisé en 2** de manière totalement transparente !
   * Quand la file retombe à `0` message (`sqs-batch-empty-alarm`), le groupe repasse à **`0` instance Spot** (*Scale-to-Zero*).

---

## 4. Analyse FinOps : Seuil de Rentabilité EC2 Spot Éphémère vs Lambda

### 4.1 Coûts de Référence (`eu-west-3` Paris)
* **EC2 `t3.micro` Spot (exécution éphémère 2h/nuit = 60h/mois) :**
  * Calcul Spot : $60\text{ h} \times 0,0031\text{ \$/h} = \mathbf{0,186\ \$/mois}$.
  * Disque EBS `gp3` (8 Go) : $\mathbf{0,70\ \$/mois}$.
  * **Total mensuel fixe pour 1 Worker Spot :** $\approx \mathbf{0,89\ \$/mois}$ (et seulement $+0,0062\text{ \$}$ si une 2ème instance Spot vient en renfort pendant 2 heures lors d'un pic !).
* **AWS Lambda (arm64, 512 Mo RAM, 3s par génération PDF) :**
  * Coût unitaire : $\approx \mathbf{0,0000202\ \$}$ par commande.

### 4.2 Seuil de Rentabilité (*Break-Even Point*)
$$N = \frac{0,89\text{ \$}}{0,0000202\text{ \$}} \approx \mathbf{44\,000\text{ commandes / mois}} \quad (\approx 1\,450\text{ commandes / jour})$$

* **En dessous de 44 000 commandes/mois :** Le Serverless (Lambda) est plus économique (et couvert par les 400 000 Go-s *Always Free*).
* **Au-delà de 44 000 commandes/mois (ou si le batch dépasse la limite stricte des 15 minutes d'une Lambda) :** L'architecture **EC2 Spot Éphémère** l'emporte avec plus de **75 % d'économies** à 200 000 commandes/mois, et la capacité de *splitter* le batch en 2 pour seulement **0,0031 $/heure** supplémentaire lors des pics !
