import os
import hmac
import hashlib
import json
import httpx
from datetime import datetime, timezone
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse, FileResponse # Added FileResponse
from pydantic import BaseModel
from motor.motor_asyncio import AsyncIOMotorClient

app = FastAPI()

MONGO_URI = os.getenv("MONGO_URI")
client = AsyncIOMotorClient(MONGO_URI)
db = client.ai_platform

class AgentPayload(BaseModel):
    client_id: str
    prompt: str
    model_choice: str

# 🌐 NATIVE STATIC LANDING PAGE ROUTER
@app.get("/")
def serve_index_page():
    # Looks for index.html sitting right next to index.py or in the parent folder root
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
    return {"status": "online", "project": "HyprCandy Workspace Gateway Pipeline"}

# 🛒 1. LEMON SQUEEZY SUBSCRIPTION EVENT INTERCEPTOR
@app.post("/api/lemonsqueezy")
async def lemonsqueezy_webhook(request: Request):
    # Enforce strict webhook provenance validation via HMAC-SHA256 handshake verification
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
    license_key = attributes.get("license_key", user_email) 
    
    if event_name == "subscription_created":
        # Initialize paid customer row profile and grant a 2.5 million token pool allowance
        await db.users.update_one(
            {"email": user_email},
            {
                "$set": {
                    "license_key": license_key,
                    "has_active_subscription": True,
                    "tier": "pro",
                    "updated_at": datetime.now(timezone.utc)
                },
                "$inc": {"credits": 2500000}
            },
            upsert=True
        )
        
    elif event_name in ["subscription_cancelled", "subscription_expired"]:
        # Block future requests instantly if subscription is explicitly closed or dropped
        await db.users.update_one(
            {"email": user_email},
            {"$set": {"has_active_subscription": False}}
        )

    return {"status": "event_processed_successfully"}

# ⚡ 2. DYNAMIC TEXT-STREAM COMPLETIONS AND AGENTIC PROXY
@app.post("/api/chat")
async def universal_agent_proxy(payload: AgentPayload):
    today_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    # 🟢 PROTOCOL A: THE FREE CONSUMER HUB (Identified via hardware execution hash)
    if payload.client_id.startswith("machine_"):
        target_url = "https://openrouter.ai"
        
        # Load OpenRouter credential mapping arrays from database collections
        key_doc = await db.api_keys.find_one({"provider": "openrouter", "isActive": True})
        if not key_doc: raise HTTPException(status_code=500, detail="Missing baseline provider configuration keys.")
        
        headers = {"Authorization": f"Bearer {key_doc['apiKey']}", "Content-Type": "application/json"}
        
        # Enforce rate-limit counters against unique hardware ID rows inside MongoDB Atlas
        usage = await db.free_usage.find_one_and_update(
            {"machine_id": payload.client_id, "date": today_date},
            {"$inc": {"count": 1}}, upsert=True, return_document=True
        )
        if usage.get("count", 0) > 50:
            raise HTTPException(status_code=429, detail="Daily threshold achieved! Upgrade to Pro via Lemon Squeezy.")

        gateway_payload = {
            "model": "openrouter/free", # Global high-availability multi-model route
            "messages": [{"role": "user", "content": payload.prompt}],
            "stream": True
        }

    # 💎 PROTOCOL B: THE PAID CORE SUBSYSTEM (Validated via Lemon Squeezy Identity key)
    else:
        # Cross-reference database rows to confirm active subscription tokens
        user = await db.users.find_one({"license_key": payload.client_id, "has_active_subscription": True})
        if not user:
            raise HTTPException(status_code=403, detail="Access Forbidden: Inactive or malformed execution key block.")
            
        if user.get("credits", 0) <= 0:
            raise HTTPException(status_code=402, detail="Payment Required: Premium token credits exhausted.")

        target_url = "https://vercel.ai"
        
        key_doc = await db.api_keys.find_one({"provider": "vercel_gateway", "isActive": True})
        if not key_doc: raise HTTPException(status_code=500, detail="Cloud environment proxy keys unmapped.")
        
        headers = {
            "Authorization": f"Bearer {key_doc['apiKey']}",
            "Content-Type": "application/json"
        }
        
        # Deduct credits uniformly on every text generation request thread loop execution
        await db.users.update_one({"license_key": payload.client_id}, {"$inc": {"credits": -1000}})

        gateway_payload = {
            "model": payload.model_choice, # Pass premium requested namespace dynamically
            "messages": [{"role": "user", "content": payload.prompt}],
            "stream": True
        }

    # Universal asynchronous SSE byte chunk forwarding array stream loop
    async def sse_stream_generator():
        async with httpx.AsyncClient(timeout=60.0) as client_connection:
            async with client_connection.stream("POST", target_url, json=gateway_payload, headers=headers) as response:
                if response.status_code != 200:
                    yield b"Error: Target processing node returned a processing error exception."
                    return
                async for stream_byte_chunk in response.aiter_bytes():
                    yield stream_byte_chunk

    return StreamingResponse(sse_stream_generator(), media_type="text/event-stream")

