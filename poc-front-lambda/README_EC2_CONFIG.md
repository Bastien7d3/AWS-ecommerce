# Fiche Technique & Configuration — EC2 Front-End de Test

Ce document détaille la configuration complète matérielle, réseau, sécurité et applicative de l'instance EC2 provisionnée dans ce module ([`ec2.tf`](./ec2.tf)).

---

## 1. Caractéristiques Matérielles (Compute & Stockage)

* **Type d'instance :** `t3.micro`
  * **Processeur :** 2 vCPU (Intel Xeon Platinum 8000)
  * **Mémoire vive (RAM) :** 1 Go
  * **Éligibilité :** **100 % AWS Free Tier** (couverte par les 750 heures/mois gratuites).
* **Disque racine (Root Volume EBS) :**
  * **Type :** `gp3` (General Purpose SSD dernière génération avec 3 000 IOPS de base)
  * **Taille :** **8 Go** (dimensionné pour respecter le plafond gratuit de 30 Go EBS mensuels)
  * **Politique de cycle de vie :** `delete_on_termination = true` (suppression automatique lors du `terraform destroy` pour éviter tout coût résiduel).

---

## 2. Système d'Exploitation & Réseau

* **Système d'exploitation (AMI) :** **Amazon Linux 2023 (`al2023`)** 64-bit x86_64 officiel AWS (`ami-0626687b379b4be48`).
* **Réseau :**
  * **Région :** `eu-west-3` (Paris)
  * **VPC :** VPC par défaut (`vpc-059af3ce7a6df81f4`), ce qui évite la création de composants réseaux payants comme les NAT Gateways.
  * **Sous-réseau :** Sous-réseau public avec attribution automatique d'une adresse IPv4 publique.

---

## 3. Sécurité Réseau (Security Group : `cloudshop-test-web-sg`)

* **Règles Entrantes (Inbound) :**
  * **Port 80 (HTTP)** ouvert depuis `0.0.0.0/0` pour permettre aux navigateurs web d'accéder à l'interface.
  * **Port 22 (SSH) fermé** : aucun port d'administration n'est exposé sur Internet, éliminant les risques d'attaques par force brute.
* **Règles Sortantes (Outbound) :**
  * Tout le trafic sortant (`0.0.0.0/0`) est autorisé pour contacter les API AWS (notamment l'API Lambda via HTTPS port 443) et télécharger les paquets du système.

---

## 4. Identité & Moindre Privilège IAM (Instance Profile)

L'instance EC2 ne possède **aucun identifiant ni clé d'accès (`AWS_ACCESS_KEY_ID`) codé en dur**.  
Elle utilise un **Profil d'Instance IAM** (`cloudshop-test-ec2-profile`) lié au rôle `cloudshop-test-ec2-role` avec une politique stricte au **moindre privilège** :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["lambda:InvokeFunction"],
      "Resource": ["arn:aws:lambda:eu-west-3:*:function:cloudshop-test-demo"]
    }
  ]
}
```

L'application web s'authentifie ainsi de manière transparente et sécurisée auprès de l'API AWS via le service de métadonnées d'instance (IMDSv2).

---

## 5. Couche Applicative (User Data & Systemd)

Au premier démarrage, le script [`user_data`](./ec2.tf) automatise l'installation et le lancement de l'application :

1. **Dépendances :** Installation du SDK officiel AWS `python3-boto3`.
2. **Code source :** Déploiement du script serveur Python [`server_src/server.py.tftpl`](./server_src/server.py.tftpl) dans `/opt/server.py`.
3. **Gestionnaire de service Linux (Systemd) :**
   * Service créé : `/etc/systemd/system/cloudshop-web.service`
   * Démarrage automatique au boot et redémarrage automatique en cas de crash (`Restart=always`, `RestartSec=3`).
   * Écoute sur le port **80** :
     * `GET /` : Sert la page d'accueil web interactive avec statistiques de l'instance.
     * `POST /api/invoke` : Déclenche l'appel vers la fonction Lambda via Boto3 et renvoie le JSON enrichi au navigateur.
