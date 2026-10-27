# Module 00 : Authentification Utilisateur (Amazon Cognito)

Ce module déploie le service d'authentification et de gestion des identités des clients de la boutique ([`main.tf`](./main.tf)).

---

## 1. Composants Déployés

1. **User Pool Cognito (`cloudshop-user-pool`) :**
   * Répertoire d'utilisateurs managé avec connexion par adresse e-mail (`username_attributes = ["email"]`).
   * Vérification automatique de l'adresse e-mail par code de confirmation à 6 chiffres.
   * Politique de mot de passe sécurisée : minimum 8 caractères, majuscule, minuscule et chiffre.
2. **App Client Cognito (`cloudshop-app-client`) :**
   * Client applicatif sans secret client (adapté au web/SPA et aux appels backend).
   * Flux d'authentification activés : `ALLOW_USER_PASSWORD_AUTH`, `ALLOW_REFRESH_TOKEN_AUTH`, `ALLOW_USER_SRP_AUTH`.
3. **Domaine d'Authentification Managé (`cloudshop-auth-fisa2026`) :**
   * Fournit l'URL d'authentification hébergée par AWS pour les flux OAuth2/OpenID Connect.

---

## 2. Fonctionnement & Intégration

* **Inscription (`POST /api/register`) :** L'utilisateur renseigne son e-mail et son mot de passe. Le serveur Front-End appelle `cognito-idp:SignUp`.
* **Confirmation (`POST /api/confirm`) :** L'utilisateur valide son compte avec le code de confirmation reçu par e-mail via `cognito-idp:ConfirmSignUp`.
* **Connexion (`POST /api/login`) :** L'utilisateur s'authentifie via `cognito-idp:InitiateAuth`, qui lui délivre un `IdToken` et un `AccessToken` JWT.
* **Sécurisation des commandes :** L'adresse e-mail vérifiée par Cognito est automatiquement injectée dans le flux de commande Lambda et dans les politiques de filtrage SNS.

---

## 3. Justification FinOps

* **Offre Always Free d'Amazon Cognito :** Jusqu'à **50 000 utilisateurs actifs par mois (MAU)** entièrement gratuits, sans limite de durée.
* Évite de déployer et maintenir une base de données d'utilisateurs dédiée ou un serveur d'authentification lourd (Keycloak, Auth0), pour un coût nul.
