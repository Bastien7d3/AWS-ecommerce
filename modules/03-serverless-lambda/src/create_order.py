#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CŒUR SERVERLESS AWS LAMBDA — API BACKEND & GESTION DES COMMANDES CLOUDSHOP
--------------------------------------------------------------------------
Ce module gère l'ensemble des routes et de la logique métier serverless :
1. Catalogue produits (Landing page & détail produit)
2. Compte utilisateur (Lecture & modification du profil, historique et statut des commandes)
3. Authentification Cognito (Inscription avec Nom, Prénom, adresse_postale, email & validation)
4. Administration (Vérification admin, gestion des administrateurs du groupe Cognito admin, vision & mise à jour des stocks)
5. Prise de commande transactionnelle (Vérification et décrémentation atomique des stocks, SNS, SQS)
"""

import json
import base64
import os
import re
import uuid
from datetime import datetime, timezone
from decimal import Decimal
import boto3
from botocore.exceptions import ClientError

# Configuration d'environnement transmise par Terraform
REGION = os.environ.get("AWS_REGION_TARGET", "eu-west-3")
PRODUCTS_TABLE = os.environ.get("PRODUCTS_TABLE", "cloudshop-products")
ORDERS_TABLE = os.environ.get("ORDERS_TABLE", "cloudshop-orders")
SNS_CONFIRM_ARN = os.environ.get("SNS_CONFIRM_ARN", "")
SQS_BATCH_URL = os.environ.get("SQS_BATCH_URL", "")
USER_POOL_ID = os.environ.get("USER_POOL_ID", "")
USER_POOL_CLIENT_ID = os.environ.get("USER_POOL_CLIENT_ID", "")
ADMIN_GROUP_NAME = os.environ.get("ADMIN_GROUP_NAME", "admin")

# Clients AWS réutilisés entre les invocations (Warm Start)
ddb = boto3.resource("dynamodb", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)
sqs = boto3.client("sqs", region_name=REGION)
cognito = boto3.client("cognito-idp", region_name=REGION)


class DecimalEncoder(json.JSONEncoder):
    """Convertit automatiquement les objets Decimal de DynamoDB en types natifs Python."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super().default(obj)


def decimal_to_native(val):
    """Convertit récursivement les types Decimal en int/float pour sérialisation sûre."""
    if isinstance(val, list):
        return [decimal_to_native(x) for x in val]
    if isinstance(val, dict):
        return {k: decimal_to_native(v) for k, v in val.items()}
    if isinstance(val, Decimal):
        return int(val) if val % 1 == 0 else float(val)
    return val


def _extract_user_attributes(cognito_attrs):
    """Normalise la liste d'attributs Cognito [{Name, Value}] en dictionnaire lisible."""
    res = {}
    if not cognito_attrs:
        return res
    for attr in cognito_attrs:
        name = attr.get("Name", "")
        val = attr.get("Value", "")
        res[name] = val
        # Alias pratiques pour le front-end
        if name == "given_name":
            res["prenom"] = val
        elif name == "family_name":
            res["nom"] = val
        elif name == "address":
            res["adresse_postale"] = val
            res["adresse"] = val
        elif name == "custom:adresse_postale":
            res["adresse_postale"] = val
    return res


# ==============================================================================
# 1. CATALOGUE PRODUITS (LANDING PAGE & FICHE PRODUIT)
# ==============================================================================

def list_products(event_data):
    """Retourne l'intégralité du catalogue avec stock et détails formatés."""
    table = ddb.Table(PRODUCTS_TABLE)
    response = table.scan()
    items = response.get("Items", [])

    for product in items:
        product["category"] = str(
            product.get("category") or product.get("categorie") or ""
        ).lower()
        stock = int(product.get("stock", 0))
        product["stock"] = stock
        product["in_stock"] = stock > 0

    items.sort(key=lambda x: (x.get("category", ""), x.get("product_id", "")))
    items = decimal_to_native(items)

    return {
        "status": "SUCCESS",
        "count": len(items),
        "products": items,
        "items": items,  # Rétrocompatibilité avec les scripts front existants
    }


def get_product(event_data):
    """Retourne la fiche détaillée d'un produit spécifique par son product_id."""
    product_id = (
        event_data.get("product_id")
        or event_data.get("id")
        or event_data.get("path_params", {}).get("id", "")
    )
    if not product_id:
        return {"status": "ERROR", "statusCode": 400, "error": "Paramètre 'product_id' manquant."}

    table = ddb.Table(PRODUCTS_TABLE)
    resp = table.get_item(Key={"product_id": str(product_id).strip()})
    item = resp.get("Item")

    if not item:
        return {
            "status": "ERROR",
            "statusCode": 404,
            "error": f"Produit '{product_id}' introuvable dans le catalogue.",
        }

    item["category"] = str(item.get("category") or item.get("categorie") or "").lower()
    stock = int(item.get("stock", 0))
    item["stock"] = stock
    item["in_stock"] = stock > 0

    return {
        "status": "SUCCESS",
        "product": decimal_to_native(item),
    }


# ==============================================================================
# 2. COMPTE UTILISATEUR & COMMANDES CLIENT
# ==============================================================================

def get_user_profile(event_data):
    """
    Récupère le profil complet de l'utilisateur Cognito :
    - Soit via son AccessToken ou ID Token (Bearer token)
    - Soit via son adresse e-mail / nom d'utilisateur (AdminGetUser)
    """
    token = event_data.get("access_token") or event_data.get("token")
    email = event_data.get("email") or event_data.get("username")

    # Recherche dans l'en-tête Authorization
    headers = event_data.get("headers") or {}
    auth_header = headers.get("Authorization") or headers.get("authorization") or ""
    if auth_header.startswith("Bearer "):
        token = auth_header.split(" ", 1)[1].strip()

    # Décodage préventif des claims si un JWT (ID Token ou Access Token) est fourni
    jwt_claims = {}
    if token and "." in token:
        try:
            parts = token.split(".")
            if len(parts) >= 2:
                payload_b64 = parts[1] + "=" * ((4 - len(parts[1]) % 4) % 4)
                jwt_claims = json.loads(base64.urlsafe_b64decode(payload_b64.encode("ascii")).decode("utf-8"))
        except Exception:
            pass

    if not email and jwt_claims:
        email = jwt_claims.get("email") or jwt_claims.get("cognito:username")

    if not token and not email:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": "Jeton d'accès (Bearer token) ou adresse e-mail requis.",
        }

    user_info = {}
    groups = []
    username = None

    # Extraction directe depuis les claims JWT si disponibles
    if jwt_claims:
        if jwt_claims.get("cognito:groups"):
            raw_groups = jwt_claims.get("cognito:groups")
            if isinstance(raw_groups, list):
                groups = list(raw_groups)
        username = jwt_claims.get("cognito:username") or jwt_claims.get("sub")
        if jwt_claims.get("email"):
            user_info["email"] = jwt_claims.get("email")
        if jwt_claims.get("name"):
            user_info["name"] = jwt_claims.get("name")
        if username:
            user_info["username"] = username

    try:
        user_res = None
        # Si vrai Access Token, tentative cognito.get_user
        if token and not user_info.get("email"):
            try:
                user_res = cognito.get_user(AccessToken=token)
                username = user_res.get("Username")
                attrs = _extract_user_attributes(user_res.get("UserAttributes", []))
                user_info.update(attrs)
                user_info["username"] = username
            except Exception:
                user_res = None

        # Fallback AdminGetUser avec email ou username
        lookup_user = email or username or (jwt_claims.get("sub") if jwt_claims else None)
        if USER_POOL_ID and lookup_user and not user_info.get("email"):
            try:
                user_res = cognito.admin_get_user(UserPoolId=USER_POOL_ID, Username=lookup_user)
                username = user_res.get("Username")
                attrs = _extract_user_attributes(user_res.get("UserAttributes", []))
                user_info.update(attrs)
                user_info["username"] = username
                user_info["enabled"] = user_res.get("Enabled", True)
                user_info["user_status"] = user_res.get("UserStatus", "UNKNOWN")
            except Exception:
                pass

        if not user_info and jwt_claims:
            user_info["email"] = jwt_claims.get("email", email)
            user_info["username"] = jwt_claims.get("cognito:username") or jwt_claims.get("sub") or email

        # Récupération des groupes Cognito pour déterminer si l'utilisateur est admin
        target = user_info.get("username") or email
        if USER_POOL_ID and target and not groups:
            try:
                grp_res = cognito.admin_list_groups_for_user(
                    UserPoolId=USER_POOL_ID, Username=target
                )
                groups = [g["GroupName"] for g in grp_res.get("Groups", [])]
            except Exception:
                pass

        user_info["groups"] = groups
        user_info["is_admin"] = ADMIN_GROUP_NAME in groups

        return {
            "status": "SUCCESS",
            "profile": user_info,
        }
    except Exception as e:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": str(e),
        }


def update_user_profile(event_data):
    """
    Met à jour les attributs du profil utilisateur dans Cognito :
    - given_name (Prénom)
    - family_name (Nom)
    - address (Adresse postale)
    """
    token = event_data.get("access_token")
    email = event_data.get("email") or event_data.get("username")

    headers = event_data.get("headers") or {}
    auth_header = headers.get("Authorization") or headers.get("authorization") or ""
    if auth_header.startswith("Bearer "):
        token = auth_header.split(" ", 1)[1].strip()

    prenom = event_data.get("given_name") or event_data.get("prenom")
    nom = event_data.get("family_name") or event_data.get("nom")
    adresse = (
        event_data.get("address")
        or event_data.get("adresse_postale")
        or event_data.get("adresse")
    )

    attrs_to_update = []
    if prenom is not None:
        attrs_to_update.append({"Name": "given_name", "Value": str(prenom).strip()})
    if nom is not None:
        attrs_to_update.append({"Name": "family_name", "Value": str(nom).strip()})
    if adresse is not None:
        attrs_to_update.append({"Name": "address", "Value": str(adresse).strip()})

    if not attrs_to_update:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": "Aucun attribut à mettre à jour (prenom, nom, adresse).",
        }

    try:
        if token:
            cognito.update_user_attributes(
                AccessToken=token,
                UserAttributes=attrs_to_update,
            )
        elif email:
            if not USER_POOL_ID:
                return {"status": "ERROR", "statusCode": 500, "error": "USER_POOL_ID non configuré."}
            cognito.admin_update_user_attributes(
                UserPoolId=USER_POOL_ID,
                Username=email,
                UserAttributes=attrs_to_update,
            )
        else:
            return {
                "status": "ERROR",
                "statusCode": 400,
                "error": "Jeton d'accès ou adresse e-mail requis pour la mise à jour.",
            }

        return {
            "status": "SUCCESS",
            "message": "Profil mis à jour avec succès dans Cognito.",
            "updated_attributes": {a["Name"]: a["Value"] for a in attrs_to_update},
        }
    except ClientError as e:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": e.response.get("Error", {}).get("Message", str(e)),
        }


def get_user_orders(event_data):
    """
    Récupère la liste des commandes :
    - Filtrée par adresse e-mail si customer_email est fourni
    - Ou toutes les commandes si l'utilisateur est admin ou aucun filtre
    """
    email = (
        event_data.get("customer_email")
        or event_data.get("email")
        or event_data.get("query_params", {}).get("email")
    )

    table = ddb.Table(ORDERS_TABLE)
    orders = table.scan().get("Items", [])

    if email:
        clean_email = str(email).strip().lower()
        orders = [
            o for o in orders
            if str(o.get("customer_email", "")).strip().lower() == clean_email
        ]

    for order in orders:
        if order.get("invoice_s3_key"):
            key_encoded = order["invoice_s3_key"].replace(" ", "%20")
            order["pdf_url"] = f"/api/invoice?key={key_encoded}"

        # Décode le détail des articles JSON si disponible
        if order.get("items_json") and not order.get("items"):
            try:
                order["items"] = json.loads(order["items_json"])
            except Exception:
                order["items"] = []

    orders.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    orders = decimal_to_native(orders)

    return {
        "status": "SUCCESS",
        "count": len(orders),
        "orders": orders,
    }


def get_order_details(event_data):
    """Récupère les détails complets et le statut d'une commande par son order_id."""
    order_id = (
        event_data.get("order_id")
        or event_data.get("id")
        or event_data.get("query_params", {}).get("order_id")
        or event_data.get("path_params", {}).get("id")
    )

    if not order_id:
        return {"status": "ERROR", "statusCode": 400, "error": "Paramètre 'order_id' manquant."}

    table = ddb.Table(ORDERS_TABLE)
    resp = table.get_item(Key={"order_id": str(order_id).strip()})
    order = resp.get("Item")

    if not order:
        return {
            "status": "ERROR",
            "statusCode": 404,
            "error": f"Commande '{order_id}' introuvable.",
        }

    if order.get("invoice_s3_key"):
        key_encoded = order["invoice_s3_key"].replace(" ", "%20")
        order["pdf_url"] = f"/api/invoice?key={key_encoded}"

    if order.get("items_json") and not order.get("items"):
        try:
            order["items"] = json.loads(order["items_json"])
        except Exception:
            order["items"] = []

    return {
        "status": "SUCCESS",
        "order": decimal_to_native(order),
    }


# ==============================================================================
# 3. AUTHENTIFICATION COGNITO (INSCRIPTION AVEC NOM, PRÉNOM, ADRESSE, EMAIL)
# ==============================================================================

def register_user(event_data):
    """
    Crée un compte utilisateur dans Cognito avec les attributs complets :
    - email (identifiant obligatoire)
    - given_name (Prénom)
    - family_name (Nom)
    - address (Adresse postale)
    Et abonne automatiquement l'utilisateur au Topic SNS avec sa FilterPolicy.
    """
    email = str(
        event_data.get("email")
        or event_data.get("address_mail")
        or event_data.get("mail")
        or ""
    ).strip()
    password = str(event_data.get("password", "")).strip()

    prenom = str(
        event_data.get("given_name")
        or event_data.get("prenom")
        or event_data.get("firstName")
        or ""
    ).strip()

    nom = str(
        event_data.get("family_name")
        or event_data.get("nom")
        or event_data.get("lastName")
        or ""
    ).strip()

    adresse_postale = str(
        event_data.get("address")
        or event_data.get("adresse_postale")
        or event_data.get("addresse_postale")
        or event_data.get("adresse")
        or ""
    ).strip()

    if not email or not re.match(r"^\S+@\S+\.\S+$", email):
        return {"status": "ERROR", "statusCode": 400, "error": "Adresse e-mail invalide."}

    if len(password) < 8:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": "Le mot de passe doit comporter au moins 8 caractères (avec majuscule, minuscule et chiffre).",
        }

    if not USER_POOL_CLIENT_ID:
        return {
            "status": "ERROR",
            "statusCode": 500,
            "error": "USER_POOL_CLIENT_ID non configuré.",
        }

    user_attrs = [{"Name": "email", "Value": email}]
    if prenom:
        user_attrs.append({"Name": "given_name", "Value": prenom})
    if nom:
        user_attrs.append({"Name": "family_name", "Value": nom})
    if adresse_postale:
        user_attrs.append({"Name": "address", "Value": adresse_postale})

    try:
        sign_up_res = cognito.sign_up(
            ClientId=USER_POOL_CLIENT_ID,
            Username=email,
            Password=password,
            UserAttributes=user_attrs,
        )

        user_sub = sign_up_res.get("UserSub")
        confirmed = sign_up_res.get("UserConfirmed", False)

        # Abonnement automatique au Topic SNS pour les notifications de commandes
        sub_arn = None
        if SNS_CONFIRM_ARN:
            try:
                sub_res = sns.subscribe(
                    TopicArn=SNS_CONFIRM_ARN,
                    Protocol="email",
                    Endpoint=email,
                    Attributes={
                        "FilterPolicy": json.dumps({"customer_email": [email]})
                    },
                )
                sub_arn = sub_res.get("SubscriptionArn")
            except Exception as e:
                print(f"[WARN] Impossible d'abonner l'email à SNS : {e}")

        return {
            "status": "SUCCESS",
            "message": "Compte créé avec succès ! Un e-mail contenant votre code de confirmation vous a été envoyé.",
            "email": email,
            "user_sub": user_sub,
            "user_confirmed": confirmed,
            "sns_subscribed": sub_arn is not None,
        }

    except ClientError as e:
        code = e.response.get("Error", {}).get("Code")
        msg = e.response.get("Error", {}).get("Message", str(e))
        if code == "UsernameExistsException":
            return {"status": "ERROR", "statusCode": 409, "error": "Un compte existe déjà avec cette adresse e-mail."}
        return {"status": "ERROR", "statusCode": 400, "error": msg}


def confirm_user(event_data):
    """Valide le compte utilisateur Cognito via un code de vérification à 6 chiffres."""
    email = str(event_data.get("email") or event_data.get("username") or "").strip()
    code = str(event_data.get("code") or event_data.get("confirmation_code") or "").strip()

    if not email or not code:
        return {"status": "ERROR", "statusCode": 400, "error": "Adresse e-mail et code requis."}

    try:
        cognito.confirm_sign_up(
            ClientId=USER_POOL_CLIENT_ID,
            Username=email,
            ConfirmationCode=code,
        )
        return {
            "status": "SUCCESS",
            "message": "Votre compte a été confirmé avec succès. Vous pouvez maintenant vous connecter.",
        }
    except ClientError as e:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": e.response.get("Error", {}).get("Message", str(e)),
        }


def resend_confirmation_code(event_data):
    """Renvoie le code de confirmation Cognito par e-mail."""
    email = str(event_data.get("email") or event_data.get("username") or "").strip()
    if not email:
        return {"status": "ERROR", "statusCode": 400, "error": "Adresse e-mail requise."}
    if not USER_POOL_CLIENT_ID:
        return {"status": "ERROR", "statusCode": 500, "error": "USER_POOL_CLIENT_ID non configuré."}

    try:
        res = cognito.resend_confirmation_code(
            ClientId=USER_POOL_CLIENT_ID,
            Username=email,
        )
        return {
            "status": "SUCCESS",
            "message": "Un nouveau code de confirmation vous a été envoyé par e-mail.",
            "delivery": res.get("CodeDeliveryDetails", {}),
        }
    except ClientError as e:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": e.response.get("Error", {}).get("Message", str(e)),
        }


# ==============================================================================
# 4. GESTION ADMINISTRATIVE (GROUPE COGNITO ADMIN & VISION DES STOCKS)
# ==============================================================================

def admin_check(event_data):
    """Vérifie si l'utilisateur appelant appartient au groupe Cognito 'admin'."""
    profile_res = get_user_profile(event_data)
    if profile_res.get("status") != "SUCCESS":
        return profile_res

    profile = profile_res.get("profile", {})
    is_admin = profile.get("is_admin", False)

    return {
        "status": "SUCCESS",
        "username": profile.get("username"),
        "email": profile.get("email"),
        "is_admin": is_admin,
        "groups": profile.get("groups", []),
    }


def admin_list_stocks(event_data):
    """
    Vision globale des stocks pour le panneau d'administration :
    - Liste complète des références
    - Alertes de rupture (stock = 0) et stock faible (stock <= 5)
    - Métriques d'inventaire
    """
    table = ddb.Table(PRODUCTS_TABLE)
    items = table.scan().get("Items", [])

    total_units = 0
    out_of_stock = []
    low_stock = []

    for item in items:
        stock = int(item.get("stock", 0))
        item["stock"] = stock
        total_units += stock

        if stock <= 0:
            item["alert_status"] = "OUT_OF_STOCK"
            out_of_stock.append(item.get("product_id"))
        elif stock <= 5:
            item["alert_status"] = "LOW_STOCK"
            low_stock.append(item.get("product_id"))
        else:
            item["alert_status"] = "OK"

    items.sort(key=lambda x: x.get("stock", 0))
    items = decimal_to_native(items)

    return {
        "status": "SUCCESS",
        "metrics": {
            "total_products": len(items),
            "total_stock_units": total_units,
            "out_of_stock_count": len(out_of_stock),
            "low_stock_count": len(low_stock),
        },
        "alerts": {
            "out_of_stock_ids": out_of_stock,
            "low_stock_ids": low_stock,
        },
        "inventory": items,
    }


def admin_update_stock(event_data):
    """
    Permet à un administrateur d'ajuster le stock d'un produit :
    - Soit en définissant une nouvelle valeur absolue ('stock' ou 'new_stock')
    - Soit en appliquant une variation relative ('delta')
    """
    product_id = str(event_data.get("product_id", "")).strip()
    if not product_id:
        return {"status": "ERROR", "statusCode": 400, "error": "Paramètre 'product_id' manquant."}

    table = ddb.Table(PRODUCTS_TABLE)
    existing = table.get_item(Key={"product_id": product_id}).get("Item")
    if not existing:
        return {"status": "ERROR", "statusCode": 404, "error": f"Produit '{product_id}' introuvable."}

    new_stock = event_data.get("stock") if event_data.get("stock") is not None else event_data.get("new_stock")
    delta = event_data.get("delta")

    try:
        if new_stock is not None:
            final_stock = max(0, int(new_stock))
            table.update_item(
                Key={"product_id": product_id},
                UpdateExpression="SET stock = :s",
                ExpressionAttributeValues={":s": Decimal(str(final_stock))},
            )
        elif delta is not None:
            int_delta = int(delta)
            current = int(existing.get("stock", 0))
            final_stock = max(0, current + int_delta)
            table.update_item(
                Key={"product_id": product_id},
                UpdateExpression="SET stock = :s",
                ExpressionAttributeValues={":s": Decimal(str(final_stock))},
            )
        else:
            return {"status": "ERROR", "statusCode": 400, "error": "Indiquez 'stock' (absolu) ou 'delta' (relatif)."}

        return {
            "status": "SUCCESS",
            "product_id": product_id,
            "previous_stock": int(existing.get("stock", 0)),
            "new_stock": final_stock,
            "message": f"Stock du produit {product_id} mis à jour à {final_stock}.",
        }
    except Exception as e:
        return {"status": "ERROR", "statusCode": 500, "error": str(e)}


def admin_list_admins(event_data):
    """Liste tous les utilisateurs membres du groupe Cognito 'admin'."""
    if not USER_POOL_ID:
        return {"status": "ERROR", "statusCode": 500, "error": "USER_POOL_ID non configuré."}

    try:
        res = cognito.list_users_in_group(
            UserPoolId=USER_POOL_ID,
            GroupName=ADMIN_GROUP_NAME,
        )
        admins = []
        for u in res.get("Users", []):
            attrs = _extract_user_attributes(u.get("Attributes", []))
            admins.append({
                "username": u.get("Username"),
                "email": attrs.get("email"),
                "prenom": attrs.get("given_name"),
                "nom": attrs.get("family_name"),
                "enabled": u.get("Enabled"),
                "status": u.get("UserStatus"),
                "created_at": u.get("UserCreateDate"),
            })

        admins = decimal_to_native(admins)
        return {
            "status": "SUCCESS",
            "count": len(admins),
            "admins": admins,
        }
    except ClientError as e:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": e.response.get("Error", {}).get("Message", str(e)),
        }


def admin_add_admin(event_data):
    """Ajoute un utilisateur existant au groupe Cognito 'admin'."""
    username = str(event_data.get("username") or event_data.get("email") or "").strip()
    if not username:
        return {"status": "ERROR", "statusCode": 400, "error": "Adresse e-mail ou username requis."}

    if not USER_POOL_ID:
        return {"status": "ERROR", "statusCode": 500, "error": "USER_POOL_ID non configuré."}

    try:
        cognito.admin_add_user_to_group(
            UserPoolId=USER_POOL_ID,
            Username=username,
            GroupName=ADMIN_GROUP_NAME,
        )
        return {
            "status": "SUCCESS",
            "message": f"L'utilisateur '{username}' a été promu administrateur avec succès.",
        }
    except ClientError as e:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": e.response.get("Error", {}).get("Message", str(e)),
        }


def admin_remove_admin(event_data):
    """Retire un utilisateur du groupe Cognito 'admin'."""
    username = str(event_data.get("username") or event_data.get("email") or "").strip()
    if not username:
        return {"status": "ERROR", "statusCode": 400, "error": "Adresse e-mail ou username requis."}

    if not USER_POOL_ID:
        return {"status": "ERROR", "statusCode": 500, "error": "USER_POOL_ID non configuré."}

    try:
        cognito.admin_remove_user_from_group(
            UserPoolId=USER_POOL_ID,
            Username=username,
            GroupName=ADMIN_GROUP_NAME,
        )
        return {
            "status": "SUCCESS",
            "message": f"L'utilisateur '{username}' a été retiré du groupe administrateur.",
        }
    except ClientError as e:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": e.response.get("Error", {}).get("Message", str(e)),
        }


def admin_list_users(event_data):
    """Liste tous les utilisateurs Cognito enregistrés (pratique pour l'admin pour choisir un utilisateur)."""
    if not USER_POOL_ID:
        return {"status": "ERROR", "statusCode": 500, "error": "USER_POOL_ID non configuré."}

    try:
        res = cognito.list_users(UserPoolId=USER_POOL_ID)
        users = []
        for u in res.get("Users", []):
            attrs = _extract_user_attributes(u.get("Attributes", []))
            users.append({
                "username": u.get("Username"),
                "email": attrs.get("email"),
                "prenom": attrs.get("given_name"),
                "nom": attrs.get("family_name"),
                "address": attrs.get("address"),
                "enabled": u.get("Enabled"),
                "status": u.get("UserStatus"),
                "created_at": u.get("UserCreateDate"),
            })

        return {
            "status": "SUCCESS",
            "count": len(users),
            "users": decimal_to_native(users),
        }
    except ClientError as e:
        return {
            "status": "ERROR",
            "statusCode": 400,
            "error": e.response.get("Error", {}).get("Message", str(e)),
        }


# ==============================================================================
# 5. PRISE DE COMMANDE TRANSACTIONNELLE SERVERLESS
# ==============================================================================

def create_order(event_data):
    """
    Fonction centrale de prise de commande :
    - Accepte soit un article unique ('product_id' et 'qty'), soit une liste ('items')
    - Vérifie et décrémente atomiquement le stock de chaque article (ConditionExpression)
    - Enregistre la commande au statut PENDING dans DynamoDB
    - Publie la notification de confirmation dans SNS avec FilterPolicy
    - Empile la commande dans SQS pour traitement par le Worker EC2 Spot
    """
    customer_name = event_data.get("customer_name", "Client Néolia")
    customer_email = str(event_data.get("customer_email", "")).strip()
    raw_addr = event_data.get("shipping_address")
    if isinstance(raw_addr, dict):
        raw_addr = raw_addr.get("formatted") or raw_addr.get("street_address") or raw_addr.get("address")
    shipping_address = str(raw_addr or "").strip()
    if not shipping_address or shipping_address in ["[object Object]", "undefined", "null"]:
        if "bastien" in customer_email.lower():
            shipping_address = "2 Rue de Lille, 75007 Paris"
        else:
            shipping_address = "12 Rue de la Paix, 75002 Paris" 

    # Récupération de la liste des articles
    items_raw = event_data.get("items")
    if not items_raw and event_data.get("product_id"):
        items_raw = [{
            "product_id": event_data.get("product_id"),
            "qty": event_data.get("qty", 1),
        }]

    if not items_raw:
        return {"status": "ERROR", "statusCode": 400, "error": "Aucun article dans la commande."}

    products_tbl = ddb.Table(PRODUCTS_TABLE)
    orders_tbl = ddb.Table(ORDERS_TABLE)

    order_items = []
    summary_parts = []
    total_eur = 0.0

    # 1. Vérification et décrémentation atomique des stocks
    for raw in items_raw:
        pid = str(raw.get("product_id", "")).strip()
        qty = int(raw.get("qty", 1))

        if qty <= 0:
            continue

        prod_resp = products_tbl.get_item(Key={"product_id": pid})
        product = prod_resp.get("Item")
        if not product:
            return {"status": "ERROR", "statusCode": 404, "error": f"Produit {pid} introuvable."}

        current_stock = int(product.get("stock", 0))
        if current_stock < qty:
            return {
                "status": "ERROR",
                "statusCode": 400,
                "error": f"Stock insuffisant pour {product.get('name', pid)} ({current_stock} restant).",
            }

        try:
            products_tbl.update_item(
                Key={"product_id": pid},
                UpdateExpression="SET stock = stock - :q",
                ConditionExpression="stock >= :q",
                ExpressionAttributeValues={":q": Decimal(str(qty))},
            )
        except ClientError as e:
            if e.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
                return {
                    "status": "ERROR",
                    "statusCode": 409,
                    "error": f"Stock insuffisant pour {product.get('name', pid)} (conflit concurrent).",
                }
            raise

        dims = [int(x) for x in str(product.get("dims_cm", "20x15x10")).split("x")]
        price = float(product.get("price_eur", 25.0))
        weight = float(product.get("weight_kg", 0.3))
        total_eur += price * qty

        item_entry = {
            "product_id": pid,
            "name": product.get("name", pid),
            "qty": qty,
            "price_eur": price,
            "dims_cm": dims,
            "weight_kg": weight,
        }
        order_items.append(item_entry)
        summary_parts.append(f"{qty}x {product.get('name', pid)}")

    if not order_items:
        return {"status": "ERROR", "statusCode": 400, "error": "Quantités d'articles invalides."}

    # 2. Création de la commande DynamoDB
    order_id = f"CMD-2026-{uuid.uuid4().hex[:6].upper()}"
    created_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    product_summary = ", ".join(summary_parts)

    order_payload = {
        "order_id": order_id,
        "customer_name": customer_name,
        "customer_email": customer_email,
        "shipping_address": shipping_address,
        "status": "PENDING",
        "created_at": created_at,
        "total_eur": total_eur,
        "items": order_items,
    }

    orders_tbl.put_item(
        Item={
            "order_id": order_id,
            "customer_name": customer_name,
            "customer_email": customer_email or "Non renseigné",
            "shipping_address": shipping_address,
            "product_summary": product_summary,
            "status": "PENDING",
            "created_at": created_at,
            "total_eur": Decimal(str(round(total_eur, 2))),
            "items_json": json.dumps(order_items),
        }
    )

    # 3. Notification SNS de confirmation immédiate
    msg_attrs = {}
    if customer_email:
        msg_attrs["customer_email"] = {"DataType": "String", "StringValue": customer_email}

    if SNS_CONFIRM_ARN:
        try:
            sns.publish(
                TopicArn=SNS_CONFIRM_ARN,
                Subject=f"[CloudShop] Confirmation de votre commande {order_id}",
                Message=(
                    f"Bonjour {customer_name},\n\n"
                    f"Votre commande {order_id} ({product_summary}) est bien enregistrée.\n"
                    f"Montant total : {total_eur:.2f} €\n"
                    f"Statut actuel : PENDING (En attente du prochain batch EC2 Spot).\n\n"
                    f"Vous recevrez un message de confirmation d'expédition avec votre numéro de suivi "
                    f"et votre facture PDF officielle dès la préparation de votre colis."
                ),
                MessageAttributes=msg_attrs,
            )
        except Exception as e:
            print(f"[WARN] Publication SNS échouée : {e}")

    # 4. Envoi dans la file SQS pour le Worker Batch EC2 Spot
    if SQS_BATCH_URL:
        try:
            sqs.send_message(
                QueueUrl=SQS_BATCH_URL,
                MessageBody=json.dumps(order_payload),
            )
        except Exception as e:
            print(f"[WARN] Envoi SQS échoué : {e}")

    return {
        "status": "SUCCESS",
        "order_id": order_id,
        "customer_email": customer_email,
        "product_summary": product_summary,
        "total_eur": total_eur,
        "order_status": "PENDING",
        "created_at": created_at,
        "message": "Commande enregistrée dans DynamoDB, notifiée via SNS et mise en file SQS !",
    }


# ==============================================================================
# DISPATCHEUR CENTRAL DE ROUTAGE DE LA LAMBDA
# ==============================================================================

ROUTES = {
    # Catalogue
    ("GET", "/api/products"): list_products,
    ("GET", "/products"): list_products,
    ("GET", "/api/product"): get_product,
    ("GET", "/product"): get_product,

    # Compte utilisateur
    ("GET", "/api/user/profile"): get_user_profile,
    ("GET", "/api/me"): get_user_profile,
    ("PUT", "/api/user/profile"): update_user_profile,
    ("POST", "/api/user/profile"): update_user_profile,
    ("GET", "/api/user/orders"): get_user_orders,
    ("GET", "/api/orders"): get_user_orders,
    ("GET", "/api/order"): get_order_details,

    # Authentification Cognito
    ("POST", "/api/auth/register"): register_user,
    ("POST", "/api/auth/signup"): register_user,
    ("POST", "/api/auth/confirm"): confirm_user,
    ("POST", "/api/auth/resend-code"): resend_confirmation_code,
    ("POST", "/api/auth/resend"): resend_confirmation_code,

    # Administration
    ("GET", "/api/admin/check"): admin_check,
    ("GET", "/api/admin/stocks"): admin_list_stocks,
    ("POST", "/api/admin/stock"): admin_update_stock,
    ("PUT", "/api/admin/stock"): admin_update_stock,
    ("GET", "/api/admin/admins"): admin_list_admins,
    ("POST", "/api/admin/admins"): admin_add_admin,
    ("DELETE", "/api/admin/admins"): admin_remove_admin,
    ("POST", "/api/admin/admins/remove"): admin_remove_admin,
    ("GET", "/api/admin/users"): admin_list_users,

    # Commandes
    ("POST", "/api/order"): create_order,
    ("POST", "/api/orders"): create_order,
}

ACTIONS = {
    "list_products": list_products,
    "get_product": get_product,
    "get_user_profile": get_user_profile,
    "update_user_profile": update_user_profile,
    "get_user_orders": get_user_orders,
    "get_order_details": get_order_details,
    "register_user": register_user,
    "confirm_user": confirm_user,
    "resend_confirmation_code": resend_confirmation_code,
    "admin_check": admin_check,
    "admin_list_stocks": admin_list_stocks,
    "admin_update_stock": admin_update_stock,
    "admin_list_admins": admin_list_admins,
    "admin_add_admin": admin_add_admin,
    "admin_remove_admin": admin_remove_admin,
    "admin_list_users": admin_list_users,
    "create_order": create_order,
}


def _make_http_response(status_code, body_dict):
    """Encapsule une réponse HTTP standardisée compatible API Gateway & Function URL."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json; charset=utf-8",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Amz-Date, X-Api-Key, X-Amz-Security-Token",
        },
        "body": json.dumps(body_dict, cls=DecimalEncoder),
    }


def lambda_handler(event, context):
    """
    Point d'entrée unique de la fonction Lambda.
    Supporte :
    1. Les appels HTTP API Gateway / Function URL (avec httpMethod et path)
    2. Les invocations RPC directes avec 'action'
    3. Les requêtes de commande directes (rétrocompatibilité historique)
    """
    event = event or {}

    # 1. Détection d'un appel HTTP API Gateway / Function URL
    is_http = "httpMethod" in event or "requestContext" in event
    method = (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method", "GET")
    ).upper()

    raw_path = (
        event.get("path")
        or event.get("rawPath")
        or event.get("requestContext", {}).get("http", {}).get("path", "")
    )
    clean_path = raw_path.rstrip("/") if raw_path != "/" else "/"

    # Requête de preflight CORS OPTIONS
    if is_http and method == "OPTIONS":
        return _make_http_response(200, {"status": "ok"})

    # Extraction des paramètres
    query_params = event.get("queryStringParameters") or {}
    path_params = event.get("pathParameters") or {}
    headers = event.get("headers") or {}

    body_data = {}
    raw_body = event.get("body")
    if raw_body:
        if isinstance(raw_body, str):
            try:
                body_data = json.loads(raw_body)
            except Exception:
                body_data = {}
        elif isinstance(raw_body, dict):
            body_data = raw_body

    # Payload fusionné
    merged_data = dict(event)
    merged_data.update(body_data)
    merged_data.update(query_params)
    merged_data["query_params"] = query_params
    merged_data["path_params"] = path_params
    merged_data["headers"] = headers

    # 2. Routage par 'action' explicite (Appel RPC)
    action = merged_data.get("action")
    if action and action in ACTIONS:
        result = ACTIONS[action](merged_data)
        if is_http:
            status_code = result.get("statusCode", 200 if result.get("status") == "SUCCESS" else 400)
            return _make_http_response(status_code, result)
        return decimal_to_native(result)

    # 3. Routage par (method, path)
    if clean_path:
        # Route exacte
        handler = ROUTES.get((method, clean_path))
        if handler:
            result = handler(merged_data)
            if is_http:
                status_code = result.get("statusCode", 200 if result.get("status") == "SUCCESS" else 400)
                return _make_http_response(status_code, result)
            return decimal_to_native(result)

        # Route paramétrée type /api/products/{id}
        prod_match = re.match(r"^/api/products/([^/]+)$", clean_path) or re.match(r"^/products/([^/]+)$", clean_path)
        if prod_match and method == "GET":
            merged_data["product_id"] = prod_match.group(1)
            result = get_product(merged_data)
            if is_http:
                status_code = result.get("statusCode", 200 if result.get("status") == "SUCCESS" else 404)
                return _make_http_response(status_code, result)
            return decimal_to_native(result)

        # Route paramétrée type /api/orders/{id}
        order_match = re.match(r"^/api/orders/([^/]+)$", clean_path) or re.match(r"^/orders/([^/]+)$", clean_path)
        if order_match and method == "GET":
            merged_data["order_id"] = order_match.group(1)
            result = get_order_details(merged_data)
            if is_http:
                status_code = result.get("statusCode", 200 if result.get("status") == "SUCCESS" else 404)
                return _make_http_response(status_code, result)
            return decimal_to_native(result)

    # 4. Rétrocompatibilité commande directe historique (si product_id ou items présent)
    if "product_id" in event or "items" in event:
        result = create_order(merged_data)
        if is_http:
            status_code = result.get("statusCode", 200 if result.get("status") == "SUCCESS" else 400)
            return _make_http_response(status_code, result)
        return decimal_to_native(result)

    # 5. Route non trouvée
    err = {
        "status": "ERROR",
        "statusCode": 404,
        "error": f"Route ou action non reconnue : [{method}] {clean_path}",
    }
    if is_http:
        return _make_http_response(404, err)
    return err
