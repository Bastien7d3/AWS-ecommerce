import json
import os
from datetime import datetime, timezone

def lambda_handler(event, context):
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    
    # Récupérer quelques infos d'exécution pour la démo
    request_id = getattr(context, 'aws_request_id', 'local-test-id')
    func_name = getattr(context, 'function_name', 'test-front-lambda')
    
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": {
            "status": "SUCCESS",
            "message": "Bonjour depuis AWS Lambda (Serverless) !",
            "timestamp": now,
            "lambda_function": func_name,
            "aws_request_id": request_id,
            "memory_limit_mb": getattr(context, 'memory_limit_in_mb', 128),
            "source": "Invoqué avec succès par le serveur Front-End EC2"
        }
    }
