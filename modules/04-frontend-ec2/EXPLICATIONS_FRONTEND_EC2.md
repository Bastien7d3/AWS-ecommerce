# Module 04 : Serveur Web Front-End EC2 & Haute Disponibilité (ALB, ASG, CloudFront)

Ce module déploie la couche de présentation de la boutique, son API applicative et l'infrastructure d'équilibrage de charge ([`main.tf`](./main.tf) et [`src/app_server.py.tftpl`](./src/app_server.py.tftpl)).

---

## 1. Composants Déployés

### A. Mode Standard (Développement & Démonstration)
* **Instance EC2 `t3.micro` (Amazon Linux 2023) :**
  * Disque racine EBS `gp3` de **8 Go** (3 000 IOPS).
  * Serveur HTTP Python géré par un service Systemd (`cloudshop-front.service`) sur le port 80.
  * Security Group filtré : port 80 ouvert aux requêtes entrantes, port SSH 22 fermé (administration sans exposition SSH).
* **Rôle IAM `front-ec2-role` :**
  * Accès sécurisé sans clé d'API codée en dur : lecture DynamoDB, invocation Lambda, lecture S3 (factures PDF), lecture des attributs SQS, gestion des abonnements SNS et lancement contrôlé d'instances via Launch Template.

### B. Mode Haute Disponibilité (`enable_autoscaling_alb = true`)
* **Application Load Balancer (ALB) Multi-AZ :** Répartit le trafic sur plusieurs zones de disponibilité de la région `eu-west-3`.
* **Auto Scaling Group (2 à 4 instances `t3.micro`) :** Ajuste dynamiquement le nombre d'instances via une politique *Target Tracking* basée sur l'utilisation CPU (seuil 60 %).
* **Distribution CloudFront (CDN Edge) :** Terminaison HTTPS globale, mise en cache des requêtes statiques et transmission d'un en-tête secret (`X-CloudFront-Secret`) garantissant que l'ALB n'accepte que les requêtes transitant par le CDN.

---

## 2. Points d'Entrée API du Serveur Web

| Route HTTP | Méthode | Rôle & Intégration AWS |
| :--- | :--- | :--- |
| `/` | `GET` | Interface web responsive de la boutique (catalogue, authentification SDK Cognito, panier, suivi et console admin). |
| `/api/products` | `GET` | Lecture en temps réel des références dans la table DynamoDB `products`. |
| `/api/subscribe` | `POST` | Abonnement automatique de l'e-mail client au Topic SNS avec `FilterPolicy` dédiée lors de l'inscription Cognito. |
| `/api/order` | `POST` | Transmission de la commande (avec jeton JWT Cognito) à la fonction AWS Lambda `cloudshop-create-order`. |
| `/api/orders` | `GET` | Consultation de l'historique et du statut des commandes dans DynamoDB. |
| `/api/invoice` | `GET` | Streaming sécurisé du fichier PDF depuis Amazon S3 (`Content-Type: application/pdf`). |
| `/api/spot-status`| `GET` | Suivi en temps réel de la file SQS et du statut des instances Worker Spot. |
| `/api/launch-spot`| `POST` | Lancement manuel d'une instance Worker Spot via le Launch Template (avec fallback automatique On-Demand). |
| `/health` | `GET` | Point de contrôle de santé utilisé par le Target Group de l'Application Load Balancer. |

---

## 3. Justification FinOps

* **Mode Mono-Instance (750h/mois Free Tier) :** Permet une exécution complète à coût nul pendant l'évaluation du projet.
* **Architecture à la demande :** L'activation du Load Balancer et du groupe d'Auto Scaling est pilotée par la variable `enable_autoscaling_alb = true`, ce qui permet de démontrer l'élasticité sans générer de coûts superflus lors des phases de développement.
