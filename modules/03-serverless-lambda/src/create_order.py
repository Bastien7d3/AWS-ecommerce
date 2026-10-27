import json
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal
import boto3

REGION = os.environ["AWS_REGION_TARGET"]
PRODUCTS_TABLE = os.environ["PRODUCTS_TABLE"]
ORDERS_TABLE = os.environ["ORDERS_TABLE"]
SNS_CONFIRM_ARN = os.environ["SNS_CONFIRM_ARN"]
SQS_BATCH_URL = os.environ["SQS_BATCH_URL"]

ddb = boto3.resource("dynamodb", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)
sqs = boto3.client("sqs", region_name=REGION)


def lambda_handler(event, context):
    """
    Fonction Lambda centrale de prise de commande :
    1. Lit le produit dans DynamoDB (table 'products') et decremente le stock
    2. Enregistre la commande au statut PENDING dans DynamoDB (table 'orders')
    3. Publie la notification de confirmation immediate dans Amazon SNS (filtree sur l'email du client)
    4. Pousse la commande dans la file Amazon SQS pour le traitement Batch EC2 Spot (periodique ou manuel)
    """
    product_id = event.get("product_id", "PROD-01")
    qty = int(event.get("qty", 1))
    customer_name = event.get("customer_name", "Client CloudShop")
    customer_email = event.get("customer_email", "").strip()
    shipping_address = event.get("shipping_address", "12 Rue de la Paix, 75002 Paris")

    products_tbl = ddb.Table(PRODUCTS_TABLE)
    orders_tbl = ddb.Table(ORDERS_TABLE)

    prod_resp = products_tbl.get_item(Key={"product_id": product_id})
    product = prod_resp.get("Item")
    if not product:
        return {"status": "ERROR", "message": f"Produit {product_id} introuvable"}

    current_stock = int(product.get("stock", 0))
    if current_stock < qty:
        return {"status": "ERROR", "message": f"Stock insuffisant ({current_stock} restant)"}

    products_tbl.update_item(
        Key={"product_id": product_id},
        UpdateExpression="SET stock = stock - :q",
        ExpressionAttributeValues={":q": Decimal(str(qty))},
    )

    order_id = f"CMD-2026-{uuid.uuid4().hex[:6].upper()}"
    created_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    dims_parts = [int(x) for x in str(product.get("dims_cm", "20x15x10")).split("x")]
    price_eur = float(product.get("price_eur", 50.0))
    weight_kg = float(product.get("weight_kg", 0.5))

    order_payload = {
        "order_id": order_id,
        "customer_name": customer_name,
        "customer_email": customer_email,
        "shipping_address": shipping_address,
        "status": "PENDING",
        "created_at": created_at,
        "items": [
            {
                "product_id": product_id,
                "name": product.get("name", "Article CloudShop"),
                "qty": qty,
                "price_eur": price_eur,
                "dims_cm": dims_parts,
                "weight_kg": weight_kg,
            }
        ],
    }

    orders_tbl.put_item(
        Item={
            "order_id": order_id,
            "customer_name": customer_name,
            "customer_email": customer_email or "Non renseigne",
            "shipping_address": shipping_address,
            "product_summary": f"{qty}x {product.get('name', product_id)}",
            "status": "PENDING",
            "created_at": created_at,
            "items_json": json.dumps(order_payload["items"]),
        }
    )

    # Attribut de filtrage SNS : permet d'envoyer l'e-mail uniquement a l'abonne correspondant a customer_email
    msg_attrs = {}
    if customer_email:
        msg_attrs["customer_email"] = {"DataType": "String", "StringValue": customer_email}

    sns.publish(
        TopicArn=SNS_CONFIRM_ARN,
        Subject=f"[CloudShop] Confirmation de votre commande {order_id}",
        Message=(
            f"Bonjour {customer_name},\n\n"
            f"Votre commande {order_id} ({qty}x {product.get('name')}) est bien enregistree.\n"
            f"Statut actuel : PENDING (En attente du prochain batch EC2 Spot).\n"
            f"Vous recevrez un second message avec votre numero de suivi et votre facture PDF des l'expedition."
        ),
        MessageAttributes=msg_attrs,
    )

    sqs.send_message(
        QueueUrl=SQS_BATCH_URL,
        MessageBody=json.dumps(order_payload),
    )

    return {
        "status": "SUCCESS",
        "order_id": order_id,
        "product": product.get("name"),
        "qty": qty,
        "customer_email": customer_email,
        "order_status": "PENDING",
        "created_at": created_at,
        "message": "Commande enregistree dans DynamoDB, notifiee via SNS et mise en attente dans SQS !",
    }
