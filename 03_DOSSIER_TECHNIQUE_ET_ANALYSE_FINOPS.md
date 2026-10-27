# Dossier Technique d'Architecture & Analyse FinOps Approfondie

**Projet :** Déploiement Boutique E-Commerce Haute Disponibilité (AWS Free Tier & Terraform)  
**Contexte :** FISA 2026 — Enseignant : Pr. Raouf Boulkroune  
**Étudiant :** Bastien | **Compte :** `689505268069` (`eu-west-3`)

---

## 1. Vue d'Ensemble de la Solution Hybride Retenue

L'architecture intègre désormais **l'élasticité native sur le Front-End (Auto Scaling Group)** et simplifie le traitement asynchrone sur un **Worker EC2 Spot éphémère** :

```mermaid
flowchart TB
    subgraph Front_Tier["1. Entrée & Front-End Élastique (IaaS Multi-AZ)"]
        User["Client Web"]
        ALB["Application Load Balancer (Public, Multi-AZ)"]
        subgraph ASG_Web["Auto Scaling Group Web (min=1, desired=2, max=4)"]
            EC2_Web1["EC2 Web Zone A (t3.micro)"]
            EC2_Web2["EC2 Web Zone B (t3.micro)"]
        end
        CW_Policy["CloudWatch Target Tracking (CPU > 60%)"]
        CW_Policy -.->|Scale-Out / Scale-In| ASG_Web
        User -->|HTTP :80| ALB
        ALB -->|Forward :80| EC2_Web1 & EC2_Web2
    end

    subgraph Serverless_Order["2. Cœur de Commande Transactionnel (Serverless)"]
        Lambda["AWS Lambda: CreateOrder (Python 3.12)"]
        DDB_Catalog[("DynamoDB: Products (Dimensions & Poids)")]
        DDB_Orders[("DynamoDB: Orders (Statuts & Suivi)")]
        SNS_Order(("Amazon SNS: OrderConfirmation"))
        
        EC2_Web1 & EC2_Web2 -->|POST /order| Lambda
        Lambda -->|Décrémente stock| DDB_Catalog
        Lambda -->|Insère commande (Status: PENDING)| DDB_Orders
        Lambda -->|Mail 1: Confirmation réception| SNS_Order
    end

    subgraph Messaging_Buffer["3. File Tampon & Rétention"]
        SQS[["Amazon SQS: batch-fulfillment-queue (Rétention 14j)"]]
        Lambda -->|Empile la commande| SQS
    end

    subgraph Async_Spot_Batch["4. Batch Éphémère EC2 Spot (Calcul Colis & Facture PDF)"]
        Spot["EC2 Spot Worker (t3.micro Spot de Nuit / Batch)"]
        S3_Bucket[("Amazon S3: Factures PDF & Audit")]
        SNS_Ship(("Amazon SNS: ShippingNotification"))
        
        SQS -->|Dépile la nuit (ou déclenchement manuel)| Spot
        Spot -->|1. Calcul Colis (S/M/L/XL) + N° Suivi| DDB_Orders
        Spot -->|2. Génère Facture PDF (fpdf2)| S3_Bucket
        Spot -->|3. Statut = SHIPPED| DDB_Orders
        Spot -->|4. Mail 2: Expédié + N° Suivi + Lien PDF| SNS_Ship
        Spot -.->|5. Auto-extinction (Scale-to-Zero)| Spot
    end
```

---

## 2. Élasticité Front-End (Auto Scaling Group EC2)

Pour répondre à l'exigence d'une plateforme **évolutive et résiliente** :
* **Déploiement Multi-AZ :** Les instances web sont réparties sur 2 sous-réseaux publics distincts (`eu-west-3a` et `eu-west-3b`).
* **Politique d'Auto Scaling :**
  * `min_size = 1` : Maintient en permanence au moins 1 serveur actif en cas de panne de zone.
  * `desired_capacity = 2` : Deux instances tournent par défaut pour absorber le trafic normal et démontrer la répartition de charge.
  * `max_size = 4` : Si le CPU moyen dépasse 60 %, une ou deux instances supplémentaires sont provisionnées automatiquement (*Scale-Out*). Dès que la charge diminue, le groupe réduit sa taille (*Scale-In*).

---

## 3. Traitement Batch sur EC2 Spot : Rôle & FinOps

### 3.1 Calcul de Dimensionnement du Colis (*Carrier Box Sizing*)
Chaque produit du catalogue possède ses dimensions $(L \times l \times h\text{ en cm})$ et son poids unitaire $(\text{kg})$. Le Worker EC2 Spot calcule le volume total cumulé (avec une marge de calage de 15 %) et le poids total de la commande, puis sélectionne automatiquement le format optimal :

| Format Transporteur | Dimensions Max $(L \times l \times h)$ | Volume Utile | Poids Max | Coût Transporteur HT |
| :--- | :---: | :---: | :---: | :---: |
| **Colis S (Small)** | $20 \times 15 \times 10\text{ cm}$ | $3\,000\text{ cm}^3$ | $2,0\text{ kg}$ | $4,90\text{ €}$ |
| **Colis M (Medium)** | $40 \times 30 \times 20\text{ cm}$ | $24\,000\text{ cm}^3$ | $10,0\text{ kg}$ | $8,90\text{ €}$ |
| **Colis L (Large)** | $60 \times 40 \times 40\text{ cm}$ | $96\,000\text{ cm}^3$ | $25,0\text{ kg}$ | $14,90\text{ €}$ |
| **Colis XL (Palette)** | $100 \times 60 \times 60\text{ cm}$ | $360\,000\text{ cm}^3$ | $100,0\text{ kg}$ | $29,90\text{ €}$ |

### 3.2 Génération Facture PDF & Notification SNS
1. Le worker attribue un **numéro de suivi transporteur unique** (ex : `TRK-EUW3-2026-C35105`).
2. Il génère la facture PDF officielle (`fpdf2`) avec le détail des lignes d'articles, la TVA (20 %), les frais de port calculés, et l'encadré logistique (format du carton, taux de remplissage).
3. Il téléverse le PDF sur **Amazon S3** (URL pré-signée).
4. Il met à jour DynamoDB (`status = SHIPPED`) et publie sur **Amazon SNS** pour envoyer un mail au client avec son numéro de suivi transporteur et le lien de téléchargement.
5. Une fois la file SQS vidée, la machine s'éteint (*Scale-to-Zero*).

---

## 4. Analyse FinOps : Seuil de Rentabilité (Break-Even Point)

* **Coût EC2 Spot en batch éphémère (2h/nuit = 60h/mois) :**
  * Calcul Spot : $60\text{ h} \times 0,0031\text{ \$/h} = 0,186\text{ \$/mois}$.
  * Disque EBS `gp3` (8 Go) : $0,70\text{ \$/mois}$.
  * **Total mensuel : $\approx \mathbf{0,89\ \$/mois}$.**
* **Coût AWS Lambda (traitement lourd binaire 3s à 512 Mo de RAM) :** $\approx \mathbf{0,0000202\ \$ / commande}$.
* **Seuil de rentabilité :**
  $$\text{Seuil} = \frac{0,89\text{ \$}}{0,0000202\text{ \$}} \approx \mathbf{44\,000\text{ commandes / mois}}$$
  * *< 44 000 commandes/mois :* Le Serverless Lambda est plus économique (inclus dans l'offre *Always Free*).
  * *> 44 000 commandes/mois :* L'EC2 Spot éphémère permet plus de 75 % d'économies et contourne le timeout strict des 15 minutes imposé par Lambda.
