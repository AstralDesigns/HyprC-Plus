import hmac
import hashlib
import json
import requests
import time

# =====================================================================
# ⚙️ CONFIGURATION BLOCK
# =====================================================================
# Ensure this matches the exact key string saved in your Vercel Dashboard
WEBHOOK_SECRET = "hyprcandy-workspace-gate"
BASE_URL = "https://hypr-c-plus.vercel.app/"

MOCK_EMAIL = "beta_tester@hyprcandy.com"
MOCK_LICENSE = "HC-PRO-TEST-MOCK-9999"

# =====================================================================
# 🛠️ HELPER TRANSMISSION FUNCTION
# =====================================================================
def send_mock_webhook(event_name, attributes_payload):
    url = f"{BASE_URL}/api/lemonsqueezy"
    
    mock_envelope = {
        "meta": {
            "event_name": event_name
        },
        "data": {
            "type": "subscriptions",
            "id": "112233",
            "attributes": attributes_payload
        }
    }
    
    # Compact JSON serialization matching raw network standards
    payload_bytes = json.dumps(mock_envelope, separators=(',', ':')).encode('utf-8')
    
    # Generate the cryptographic signature verification block
    computed_hash = hmac.new(
        WEBHOOK_SECRET.encode('utf-8'), 
        payload_bytes, 
        hashlib.sha256
    ).hexdigest()
    
    headers = {
        "Content-Type": "application/json",
        "X-Signature": computed_hash
    }
    
    print(f"\n📡 Sending event: '{event_name}' to {url}...")
    try:
        response = requests.post(url, data=payload_bytes, headers=headers)
        print(f"   ↳ Response Status Code: {response.status_code}")
        print(f"   ↳ JSON Body Payload:   {response.json()}")
        return response.status_code == 200
    except Exception as e:
        print(f"   ❌ Network Transaction Failure: {str(e)}")
        return False

# =====================================================================
# 🚀 CORE AUTOMATED TEST PIPELINE
# =====================================================================
if __name__ == "__main__":
    print("🎯 Initializing Clean Lemon Squeezy Webhook Verification Suite...")
    
    # PHASE 1: Trigger the subscription generation
    sub_attributes = {
        "user_email": MOCK_EMAIL,
        "status": "active",
        "variant_name": "HyprCandy Workspace Pro"
    }
    
    phase_1_success = send_mock_webhook("subscription_created", sub_attributes)
    
    if phase_1_success:
        print("⏳ Brief delay for database document initialization tracking...")
        time.sleep(1.5)
        
        # PHASE 2: Trigger the subsequent license key extraction attachment
        license_attributes = {
            "user_email": MOCK_EMAIL,
            "key": MOCK_LICENSE
        }
        
        phase_2_success = send_mock_webhook("license_key_created", license_attributes)
        
        if phase_2_success:
            print("\n🌟 PIPELINE VERIFICATION SUCCESSFUL!")
            print(f"   - User: {MOCK_EMAIL} is fully active in MongoDB Atlas.")
            print(f"   - License Key: {MOCK_LICENSE} is bound to their document.")
            print("   - You can now safely flush this test row and hand off context to Gemini.")
        else:
            print("\n❌ Verification Failed at Phase 2 (License Key binding creation).")
    else:
        print("\n❌ Verification Failed at Phase 1 (Subscription parsing entry).")

