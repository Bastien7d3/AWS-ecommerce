# 📖 Guide de l'API Backend pour le Développeur Front-End

Ce guide détaille l'ensemble des routes HTTP exposées par le backend (Lambda Serverless et passerelle EC2/ALB) pour les 4 fonctionnalités de la boutique.

Toutes les routes supportent **CORS** (`Access-Control-Allow-Origin: *`) et peuvent être appelées directement depuis votre environnement de développement local (ex: `http://localhost:3000`, `http://localhost:5173`) ou depuis le nom de domaine de l'ALB/CloudFront.

---

## Sommaire des Fonctionnalités & Endpoints

| Fonctionnalité | Méthode | Route HTTP | Rôle & Paramètres |
| :--- | :--- | :--- | :--- |
| **1. Landing Page & Produits** | `GET` | `/api/products` | Liste de tous les produits avec stock et catégories. |
| | `GET` | `/api/products/{id}` ou `/api/product?id={id}` | Fiche détaillée d'un produit par son identifiant. |
| **2. Compte Utilisateur** | `GET` | `/api/user/profile` ou `/api/me` | Voir le profil Cognito (Nom, Prénom, Adresse, email, rôles). |
| | `PUT` / `POST` | `/api/user/profile` | Modifier ses informations (nom, prénom, adresse). |
| | `GET` | `/api/user/orders?email={email}` | Historique des commandes d'un utilisateur et statut en direct. |
| | `GET` | `/api/order?order_id={id}` | Détail et suivi complet d'une commande spécifique. |
| **3. Inscription Cognito** | `POST` | `/api/auth/register` | Inscription avec Nom, Prénom, adresse_postale et e-mail. |
| | `POST` | `/api/auth/confirm` | Confirmation par code de vérification à 6 chiffres. |
| **4. Espace Administration** | `GET` | `/api/admin/check` | Vérifier si l'utilisateur connecté appartient au groupe `admin`. |
| | `GET` | `/api/admin/stocks` | **Vision des stocks :** alertes rupture (0), stock faible (≤5), métriques. |
| | `POST` / `PUT` | `/api/admin/stock` | Ajuster le stock d'un produit (`stock` absolu ou `delta` relatif). |
| | `GET` | `/api/admin/admins` | Lister tous les membres du groupe Cognito `admin`. |
| | `POST` | `/api/admin/admins` | Ajouter un utilisateur existant au groupe `admin`. |
| | `DELETE` / `POST` | `/api/admin/admins/remove` | Retirer un utilisateur du groupe `admin`. |
| | `GET` | `/api/admin/users` | Lister tous les utilisateurs Cognito enregistrés. |
| **5. Prise de Commande** | `POST` | `/api/order` | Validation panier (1 ou N articles), décrémentation atomique, SNS, SQS. |

---

## 1. Landing Page & Détail des Produits

### A. Liste de tous les produits
* **Endpoint :** `GET /api/products`
* **Exemple de réponse (200 OK) :**
```json
[
  {
    "product_id": "ATN-VIS-001",
    "name": "Gel Nettoyant Minéral",
    "category": "visage",
    "description": "Nettoyant doux aux minéraux, pour une peau nette sans sensation de tiraillement.",
    "price_eur": 24.0,
    "stock": 30,
    "in_stock": true,
    "dims_cm": "5x5x16",
    "weight_kg": 0.22
  },
  {
    "product_id": "ATN-PAR-001",
    "name": "Eau de Parfum Sillage 01",
    "category": "parfums",
    "description": "Accord boisé et ambré, profond et contemporain. Format 50 ml.",
    "price_eur": 89.0,
    "stock": 12,
    "in_stock": true,
    "dims_cm": "7x7x13",
    "weight_kg": 0.32
  }
]
```

> **Astuce Front :** Si vous souhaitez obtenir l'objet avec métadonnées (`count`, `status`), ajoutez `?format=full` à l'URL.

### B. Détail d'un produit spécifique
* **Endpoint :** `GET /api/products/{product_id}` ou `GET /api/product?id={product_id}`
* **Exemple :** `GET /api/products/ATN-VIS-001`
* **Exemple de réponse (200 OK) :**
```json
{
  "status": "SUCCESS",
  "product": {
    "product_id": "ATN-VIS-001",
    "name": "Gel Nettoyant Minéral",
    "category": "visage",
    "description": "Nettoyant doux aux minéraux, pour une peau nette sans sensation de tiraillement.",
    "price_eur": 24.0,
    "stock": 30,
    "in_stock": true,
    "dims_cm": "5x5x16",
    "weight_kg": 0.22
  }
}
```

---

## 2. Page de Compte (Infos & Commandes)

### A. Consulter son profil utilisateur
* **Endpoint :** `GET /api/user/profile` ou `GET /api/me`
* **Headers :** `Authorization: Bearer <AccessToken>` (recommandé) ou Query param : `?email=client@domaine.fr`
* **Exemple de réponse (200 OK) :**
```json
{
  "status": "SUCCESS",
  "profile": {
    "username": "client@domaine.fr",
    "email": "client@domaine.fr",
    "prenom": "Jean",
    "nom": "Dupont",
    "given_name": "Jean",
    "family_name": "Dupont",
    "adresse_postale": "15 Avenue des Champs, 75008 Paris",
    "address": "15 Avenue des Champs, 75008 Paris",
    "groups": [],
    "is_admin": false,
    "user_status": "CONFIRMED",
    "enabled": true
  }
}
```

### B. Modifier ses informations personnelles
* **Endpoint :** `PUT /api/user/profile` ou `POST /api/user/profile`
* **Headers :** `Authorization: Bearer <AccessToken>` (ou passer `email` dans le body)
* **Corps de la requête (JSON) :**
```json
{
  "prenom": "Jean-Pierre",
  "nom": "Dupont",
  "adresse_postale": "22 Rue de la Paix, 75002 Paris"
}
```
*Note : Le backend accepte indifféremment `prenom` ou `given_name`, `nom` ou `family_name`, `adresse_postale` ou `address`.*
* **Exemple de réponse (200 OK) :**
```json
{
  "status": "SUCCESS",
  "message": "Profil mis à jour avec succès dans Cognito.",
  "updated_attributes": {
    "given_name": "Jean-Pierre",
    "family_name": "Dupont",
    "address": "22 Rue de la Paix, 75002 Paris"
  }
}
```

### C. Historique des commandes de l'utilisateur
* **Endpoint :** `GET /api/user/orders?email=client@domaine.fr`
* **Exemple de réponse (200 OK) :**
```json
{
  "status": "SUCCESS",
  "count": 1,
  "orders": [
    {
      "order_id": "CMD-2026-A1B2C3",
      "created_at": "2026-10-28 10:15:30 UTC",
      "customer_email": "client@domaine.fr",
      "customer_name": "Jean Dupont",
      "shipping_address": "22 Rue de la Paix, 75002 Paris",
      "status": "SHIPPED",
      "tracking_number": "TRK-FR-789012",
      "box_size": "M",
      "product_summary": "1x Gel Nettoyant Minéral, 1x Baume Structurant",
      "total_eur": 50.0,
      "pdf_url": "/api/invoice?key=factures/CMD-2026-A1B2C3.pdf",
      "items": [
        {
          "product_id": "ATN-VIS-001",
          "name": "Gel Nettoyant Minéral",
          "qty": 1,
          "price_eur": 24.0
        },
        {
          "product_id": "ATN-BAR-002",
          "name": "Baume Structurant",
          "qty": 1,
          "price_eur": 26.0
        }
      ]
    }
  ]
}
```

### D. Détail d'une commande
* **Endpoint :** `GET /api/order?order_id=CMD-2026-A1B2C3` ou `GET /api/orders/CMD-2026-A1B2C3`

---

## 3. Inscription & Création de Compte Cognito

### A. Inscription d'un nouveau compte
* **Endpoint :** `POST /api/auth/register` (ou `/api/auth/signup`)
* **Corps de la requête (JSON) :**
```json
{
  "email": "nouveau.client@domaine.fr",
  "password": "MonMotDePasse123!",
  "prenom": "Sophie",
  "nom": "Lefevre",
  "adresse_postale": "8 Quai de la Loire, 44000 Nantes"
}
```
* **Exemple de réponse (200 OK) :**
```json
{
  "status": "SUCCESS",
  "message": "Compte créé et activé immédiatement ! Aucune vérification requise, vous pouvez vous connecter.",
  "email": "nouveau.client@domaine.fr",
  "user_sub": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "user_confirmed": true,
  "sns_subscribed": true
}
```
*(Le compte est immédiatement activé et utilisable sans aucune étape de validation par lien ou par code. L'utilisateur peut se connecter aussitôt avec ses identifiants).*

### B. Validation du compte par code
* **Endpoint :** `POST /api/auth/confirm`
* **Corps de la requête (JSON) :**
```json
{
  "email": "nouveau.client@domaine.fr",
  "code": "123456"
}
```

---

## 4. Espace Administration (Groupe Cognito Admin & Stocks)

### A. Vérifier les droits d'administration
* **Endpoint :** `GET /api/admin/check`
* **Headers :** `Authorization: Bearer <AccessToken>` ou query `?email=admin@domaine.fr`
* **Exemple de réponse :**
```json
{
  "status": "SUCCESS",
  "email": "admin@domaine.fr",
  "is_admin": true,
  "groups": ["admin"]
}
```

### B. Vision des stocks & alertes
* **Endpoint :** `GET /api/admin/stocks`
* **Exemple de réponse (200 OK) :**
```json
{
  "status": "SUCCESS",
  "metrics": {
    "total_products": 12,
    "total_stock_units": 218,
    "out_of_stock_count": 0,
    "low_stock_count": 1
  },
  "alerts": {
    "out_of_stock_ids": [],
    "low_stock_ids": ["ATN-PAR-002"]
  },
  "inventory": [
    {
      "product_id": "ATN-PAR-002",
      "name": "Eau de Parfum Minuit",
      "stock": 9,
      "alert_status": "OK",
      "price_eur": 95.0,
      "category": "parfums"
    },
    {
      "product_id": "ATN-VIS-001",
      "name": "Gel Nettoyant Minéral",
      "stock": 30,
      "alert_status": "OK",
      "price_eur": 24.0,
      "category": "visage"
    }
  ]
}
```

### C. Mettre à jour le stock d'un produit
* **Endpoint :** `POST /api/admin/stock` ou `PUT /api/admin/stock`
* **Option 1 : Définir une nouvelle valeur absolue (`stock`) :**
```json
{
  "product_id": "ATN-VIS-001",
  "stock": 50
}
```
* **Option 2 : Appliquer une variation relative (`delta`) :**
```json
{
  "product_id": "ATN-VIS-001",
  "delta": 10
}
```
* **Exemple de réponse (200 OK) :**
```json
{
  "status": "SUCCESS",
  "product_id": "ATN-VIS-001",
  "previous_stock": 30,
  "new_stock": 50,
  "message": "Stock du produit ATN-VIS-001 mis à jour à 50."
}
```

### D. Gestion des administrateurs

#### 1. Lister les administrateurs
* **Endpoint :** `GET /api/admin/admins`
```json
{
  "status": "SUCCESS",
  "count": 1,
  "admins": [
    {
      "username": "admin@domaine.fr",
      "email": "admin@domaine.fr",
      "prenom": "Admin",
      "nom": "CloudShop",
      "enabled": true,
      "status": "CONFIRMED"
    }
  ]
}
```

#### 2. Ajouter un utilisateur au groupe `admin`
* **Endpoint :** `POST /api/admin/admins` (ou `/api/admin/admins/add`)
```json
{
  "username": "nouveau.collaborateur@domaine.fr"
}
```
*Réponse :*
```json
{
  "status": "SUCCESS",
  "message": "L'utilisateur 'nouveau.collaborateur@domaine.fr' a été promu administrateur avec succès."
}
```

#### 3. Retirer un utilisateur du groupe `admin`
* **Endpoint :** `DELETE /api/admin/admins` ou `POST /api/admin/admins/remove`
```json
{
  "username": "collaborateur@domaine.fr"
}
```

#### 4. Lister tous les utilisateurs enregistrés
* **Endpoint :** `GET /api/admin/users`
*(Permet à l'admin de voir la liste de tous les comptes créés pour en promouvoir un en un clic).*

---

## 5. Prise de Commande (Panier)

* **Endpoint :** `POST /api/order`
* **Corps de la requête (JSON) :**
```json
{
  "customer_name": "Jean Dupont",
  "customer_email": "jean.dupont@domaine.fr",
  "shipping_address": "22 Rue de la Paix, 75002 Paris",
  "items": [
    { "product_id": "ATN-VIS-001", "qty": 2 },
    { "product_id": "ATN-PAR-001", "qty": 1 }
  ]
}
```
* **Exemple de réponse (200 OK) :**
```json
{
  "status": "ok",
  "order_id": "CMD-2026-E4F5A6",
  "order_ids": ["CMD-2026-E4F5A6"],
  "total_eur": 137.0,
  "product_summary": "2x Gel Nettoyant Minéral, 1x Eau de Parfum Sillage 01",
  "order_status": "PENDING",
  "message": "Commande enregistrée dans DynamoDB, notifiée via SNS et mise en file SQS !"
}
```
