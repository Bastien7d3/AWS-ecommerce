# Module 00 : Authentification Utilisateur (Amazon Cognito)

Ce module déploie le service d'authentification et de gestion des identités des clients de la boutique ([`main.tf`](./main.tf)).

---

## 1. Composants Déployés

1. **User Pool Cognito (`cloudshop-user-pool`) :**
   * Répertoire d'utilisateurs managé avec connexion par adresse e-mail (`username_attributes = ["email"]`).
   * Vérification automatique de l'adresse e-mail par lien de confirmation cliquable (`CONFIRM_WITH_LINK`).
   * Politique de mot de passe sécurisée : minimum 8 caractères, majuscule, minuscule et chiffre.
2. **App Client Cognito (`cloudshop-app-client`) :**
   * Client applicatif sans secret client (adapté au web/SPA et aux appels depuis le navigateur via le SDK `amazon-cognito-identity-js`).
   * Flux d'authentification activés : `ALLOW_USER_PASSWORD_AUTH`, `ALLOW_REFRESH_TOKEN_AUTH`, `ALLOW_USER_SRP_AUTH`.
3. **Domaine d'Authentification Managé (`cloudshop-auth-fisa2026`) :**
   * Fournit le domaine hébergé par AWS requis par Cognito pour générer et valider les liens d'activation envoyés par e-mail.

---

## 2. Fonctionnement & Intégration

* **Inscription (`signUp` SDK JS + `POST /api/subscribe`) :** L'utilisateur renseigne son e-mail et son mot de passe sur le Front-End. Le navigateur appelle directement `userPool.signUp()` vers Amazon Cognito, puis déclenche `POST /api/subscribe` sur le serveur pour abonner automatiquement son e-mail au Topic SNS avec un filtre dédié (`FilterPolicy`).
* **Activation par lien e-mail (`CONFIRM_WITH_LINK`) :** L'utilisateur clique sur le lien d'activation reçu par e-mail de la part d'Amazon Cognito (ainsi que sur le lien *Confirm subscription* d'Amazon SNS).
* **Connexion (`authenticateUser` SRP) :** L'utilisateur s'authentifie directement auprès de Cognito via le protocole SRP (`AmazonCognitoIdentity`), qui lui délivre un `IdToken` JWT stocké en session.
* **Sécurisation des commandes :** L'adresse e-mail vérifiée et le jeton JWT Cognito sont associés à la validation du panier vers la fonction Lambda et aux politiques de filtrage SNS.

---

## 3. Justification FinOps

* **Offre Always Free d'Amazon Cognito :** Jusqu'à **50 000 utilisateurs actifs par mois (MAU)** entièrement gratuits, sans limite de durée.
* Évite de déployer et maintenir une base de données d'utilisateurs dédiée ou un serveur d'authentification lourd (Keycloak, Auth0), pour un coût nul.
