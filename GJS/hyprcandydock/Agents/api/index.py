import os
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import HTMLResponse # <--- ADDED
from motor.motor_asyncio import AsyncIOMotorClient
from pydantic import BaseModel

app = FastAPI()

# Connect to MongoDB using an environment variable (We will set this up in Vercel)
MONGO_URI = os.getenv("MONGO_URI")
client = AsyncIOMotorClient(MONGO_URI)
db = client.ai_platform

# Schema for the requests your desktop app will send to query the AI
class PromptRequest(BaseModel):
    license_key: str
    prompt: str

# 0. ROOT LANDING PAGE: Serves your compliance site for Stripe/Paddle auditors
@app.get("/", response_class=HTMLResponse)
async def read_root():
    # Targets index.html sitting one level above this script in the Agents folder
    path_to_html = os.path.join(os.path.dirname(__file__), "../index.html")
    try:
        with open(path_to_html, "r", encoding="utf-8") as file:
            return file.read()
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Landing page file missing on server root")

@app.get("/api")
def hello_world():
    return {"message": "HyprCandy Workspace Backend API is Online"}

# 1. GUMROAD WEBHOOK: Pinned from your Gumroad Advanced Dashboard
@app.post("/api/gumroad")
async def gumroad_webhook(request: Request):
    # Gumroad sends webhooks as Form Data by default
    form_data = await request.form()
    
    email = form_data.get("email")
    license_key = form_data.get("license_key")
    
    if not email or not license_key:
        raise HTTPException(status_code=400, detail="Malformed webhook data")
        
    # Save the buyer to your MongoDB cluster
    await db.users.update_one(
        {"license_key": license_key},
        {
            "$set": {
                "email": email,
                "has_active_subscription": True
            },
            "$inc": {"credits": 50000} # Gift 50,000 tokens on purchase
        },
        upsert=True
    )
    return {"status": "verified_and_saved"}

# 2. DESKTOP INTERACTION: Called by your Hyprland workspace configuration
@app.post("/api/chat")
async def chat_proxy(payload: PromptRequest):
    # Verify the user exists in your database
    user = await db.users.find_one({"license_key": payload.license_key})
    
    if not user or not user.get("has_active_subscription"):
        raise HTTPException(status_code=403, detail="Invalid License Key or Inactive Account")
        
    if user.get("credits", 0) <= 0:
        raise HTTPException(status_code=402, detail="Out of AI credits")
        
    # TODO: Connect to Groq/Google AI Studio here, get response, 
    # deduct credits, and return response back to the desktop launcher.
    
    return {"response": f"Backend verified key! Processing prompt: {payload.prompt}"}
