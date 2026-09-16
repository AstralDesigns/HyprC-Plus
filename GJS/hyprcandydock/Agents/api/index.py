import os
import hmac
import hashlib
import json
import httpx
from datetime import datetime, timezone
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse, FileResponse
from pydantic import BaseModel
from motor.motor_asyncio import AsyncIOMotorClient

app = FastAPI()

MONGO_URI = os.getenv("MONGO_URI")
client = AsyncIOMotorClient(MONGO_URI)
db = client.ai_platform

# Optimized schema exclusively for Paid Workspace users
class AgentPayload(BaseModel):
    license_key: str        # The user's active Lemon Squeezy license key
    prompt: str             # Context buffer sent from Monaco Editor
    model_choice: str       # Premium model id chosen via the UI selector

# 🌐 NATIVE STATIC LANDING PAGE ROUTER
@app.get("/")
def serve_index_page():
    possible_paths = [
        "index.html",
        "../index.html",
        os.path.join(os.path.dirname(__file__), "index.html"),
        os.path.join(os.path.dirname(__file__), "../index.html")
    ]
    for path in possible_paths:
        if os.path.exists(path):
            return FileResponse(path)
    raise HTTPException(status_code=404, detail="index.html structural asset not found.")

@app.get("/api")
def hello_world():
    return {"status": "online", "project": "HyprCandy Premium Workspace Gateway"}

# 🛒 1. LEMON SQUEEZY SUBSCRIPTION EVENT INTERCEPTOR
@app.post("/api/lemonsqueezy")
async def lemonsqueezy_webhook(request: Request):
    webhook_secret = os.getenv("LEMON_SQUEEZY_WEBHOOK_SECRET")
    if not webhook_secret:
        raise HTTPException(status_code=500, detail="Cloud environment signature secret unmapped.")
        
    body = await request.body()
    signature = request.headers.get("X-Signature")
    
    if not signature:
        raise HTTPException(status_code=401, detail="Security validation header absent.")
        
    local_hash = hmac.new(webhook_secret.encode(), body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(local_hash, signature):
        raise HTTPException(status_code=401, detail="Cryptographic token mismatch. Forbidden payload signature.")

    payload = json.loads(body.decode())
    event_name = payload.get("meta", {}).get("event_name")
    attributes = payload.get("data", {}).get("attributes", {})
    user_email = attributes.get("user_email")

    if event_name == "subscription_created":
        await db.users.update_one(
            {"email": user_email},
            {
                "$set": {
                    "has_active_subscription": True,
                    "tier": "pro",
                    "updated_at": datetime.now(timezone.utc)
                },
                "$inc": {"credits": 2500000}  # Allocate 2.5M baseline tokens
            },
            upsert=True
        )

    elif event_name == "license_key_created":
        license_key = attributes.get("key")
        if user_email and license_key:
            await db.users.update_one(
                {"email": user_email},
                {
                    "$set": {
                        "license_key": license_key,
                        "updated_at": datetime.now(timezone.utc)
                    }
                },
                upsert=True
            )

    elif event_name in ["subscription_cancelled", "subscription_expired"]:
        await db.users.update_one(
            {"email": user_email},
            {"$set": {"has_active_subscription": False}}
        )

    return {"status": "event_processed_successfully"}

# 💎 2. DYNAMIC PREMIUM TEXT-STREAM COMPLETIONS GATEWAY
@app.post("/api/chat")
async def premium_agent_proxy(payload: AgentPayload):
    # Cross-reference MongoDB collections to confirm an active premium license row matches
    user = await db.users.find_one({"license_key": payload.license_key, "has_active_subscription": True})
    if not user:
        raise HTTPException(status_code=403, detail="Access Forbidden: Inactive or malformed workspace key.")
        
    if user.get("credits", 0) <= 0:
        raise HTTPException(status_code=402, detail="Payment Required: Premium token credits completely exhausted.")

    # Your Vercel AI Gateway endpoint route
    target_url = "https://vercel.ai"
    
    # Load Vercel master proxy credential from database documents
    key_doc = await db.api_keys.find_one({"provider": "vercel_gateway", "isActive": True})
    if not key_doc: 
        raise HTTPException(status_code=500, detail="Cloud environment gateway configuration keys unmapped.")
    
    headers = {
        "Authorization": f"Bearer {key_doc['apiKey']}",
        "Content-Type": "application/json"
    }
    
    # Deduct credits from user profile balance uniformly on successful transaction handshakes
    await db.users.update_one({"license_key": payload.license_key}, {"$inc": {"credits": -1000}})

    gateway_payload = {
        "model": payload.model_choice,  # Pass premium requested namespace dynamically (e.g., gpt-4o)
        "messages": [{"role": "user", "content": payload.prompt}],
        "stream": True
    }

    # Asynchronous Server-Sent Events (SSE) byte chunk forwarding streaming loop
    async def sse_stream_generator():
        async with httpx.AsyncClient(timeout=60.0) as client_connection:
            async with client_connection.stream("POST", target_url, json=gateway_payload, headers=headers) as response:
                if response.status_code != 200:
                    yield b"Error: Upstream endpoint node returned a text generation handling exception."
                    return
                async for stream_byte_chunk in response.aiter_bytes():
                    yield stream_byte_chunk

    return StreamingResponse(sse_stream_generator(), media_type="text/event-stream")

