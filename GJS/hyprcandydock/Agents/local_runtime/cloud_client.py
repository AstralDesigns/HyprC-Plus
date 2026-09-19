"""
cloud_client.py — Vercel AI Gateway cloud client for HyprCandy Agent

Routes SSE completions through https://hypr-c-plus.vercel.app/api/chat
using a validated Lemon Squeezy license key.

Exposes:
  - validate_license(key) -> dict          License key validation
  - get_credits(key) -> int                Remaining token balance
  - stream_cloud(messages, model, key) -> AsyncIterator[dict]
      Yields same event types as local_backend in agent_loop.py
"""

from __future__ import annotations

import json
from typing import AsyncIterator

import httpx

PROXY_BASE = "https://hypr-c-plus.vercel.app"
CHAT_ENDPOINT = f"{PROXY_BASE}/api/chat"

# Available cloud models (white-label IDs — no provider branding in UI)
CLOUD_MODELS = [
    {
        "id": "google/gemini-2.5-flash",
        "name": "Gemini 2.5 Flash",
        "description": "Google's fastest multimodal model. Great for fast code and analysis tasks.",
        "context": "1M tokens",
    },
    {
        "id": "meta-llama/llama-3.3-70b-instruct",
        "name": "Llama 3.3 70B",
        "description": "Meta's flagship open model. Excellent reasoning and instruction following.",
        "context": "128k tokens",
    },
    {
        "id": "anthropic/claude-sonnet-4-5",
        "name": "Claude Sonnet 4.5",
        "description": "Anthropic's balanced model. Superior code generation and analysis.",
        "context": "200k tokens",
    },
    {
        "id": "openai/gpt-4o",
        "name": "GPT-4o",
        "description": "OpenAI's multimodal flagship. Strong at structured output and tools.",
        "context": "128k tokens",
    },
]


async def validate_license(key: str) -> dict:
    """
    Validate a Lemon Squeezy license key against the Vercel backend.
    Returns {"valid": bool, "credits": int, "tier": str}.
    """
    if not key or not key.strip():
        return {"valid": False, "credits": 0, "tier": None, "error": "No key provided"}

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            # Send a minimal probe request — 403 = bad key, 402 = out of credits, 200 = valid
            resp = await client.post(
                CHAT_ENDPOINT,
                json={
                    "client_id": key.strip(),
                    "prompt": "__license_check__",
                    "model_choice": "google/gemini-2.5-flash",
                },
                headers={"Content-Type": "application/json"},
            )
            if resp.status_code == 403:
                return {"valid": False, "credits": 0, "tier": None, "error": "Invalid or inactive license key"}
            if resp.status_code == 402:
                return {"valid": True, "credits": 0, "tier": "pro", "error": "Credits exhausted"}
            if resp.status_code == 200:
                return {"valid": True, "credits": -1, "tier": "pro"}
            return {"valid": False, "credits": 0, "tier": None, "error": f"Unexpected status: {resp.status_code}"}
    except httpx.ConnectError:
        return {"valid": False, "credits": 0, "tier": None, "error": "Cannot reach HyprCandy cloud (offline?)"}
    except Exception as exc:
        return {"valid": False, "credits": 0, "tier": None, "error": str(exc)}


async def stream_cloud(
    messages: list[dict],
    model_choice: str,
    license_key: str,
) -> AsyncIterator[dict]:
    """
    Stream completions from the Vercel AI Gateway.
    Yields same event dicts as local_backend in agent_loop.py:
      {"type": "token", "content": str}
      {"type": "tool_calls", "calls": [...]}
      {"type": "done"}
      {"type": "error", "message": str}

    NOTE: The cloud proxy endpoint currently accepts a flat `prompt` string.
    We serialize the full message history as a structured block so the
    cloud model has complete context while staying compatible with the
    locked api/index.py AgentPayload schema.
    """
    # Serialize messages into a structured prompt block
    def _format_messages(msgs: list[dict]) -> str:
        parts = []
        for m in msgs:
            role = m.get("role", "user")
            content = m.get("content") or ""
            if role == "system":
                parts.append(f"[SYSTEM]\n{content}")
            elif role == "user":
                parts.append(f"[USER]\n{content}")
            elif role == "assistant":
                parts.append(f"[ASSISTANT]\n{content}")
            elif role == "tool":
                parts.append(f"[TOOL RESULT]\n{content}")
        return "\n\n".join(parts)

    prompt = _format_messages(messages)
    payload = {
        "client_id": license_key,
        "prompt": prompt,
        "model_choice": model_choice,
    }

    tool_call_buffer: dict[str, dict] = {}

    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            async with client.stream(
                "POST",
                CHAT_ENDPOINT,
                json=payload,
                headers={"Content-Type": "application/json"},
            ) as resp:
                if resp.status_code == 403:
                    yield {"type": "error", "message": "Cloud access denied: invalid or inactive license key"}
                    return
                if resp.status_code == 402:
                    yield {"type": "error", "message": "Cloud credits exhausted. Top up at hypr-c-plus.vercel.app"}
                    return
                if not resp.is_success:
                    body = await resp.aread()
                    yield {"type": "error", "message": f"Cloud error {resp.status_code}: {body[:200].decode()}"}
                    return

                buffer = ""
                async for raw_chunk in resp.aiter_bytes(1024):
                    buffer += raw_chunk.decode(errors="replace")
                    while "\n" in buffer:
                        line, buffer = buffer.split("\n", 1)
                        line = line.strip()
                        if not line or not line.startswith("data:"):
                            continue
                        data = line[5:].strip()
                        if data == "[DONE]":
                            break
                        try:
                            chunk = json.loads(data)
                        except json.JSONDecodeError:
                            continue

                        choice = (chunk.get("choices") or [{}])[0]
                        delta = choice.get("delta", {})

                        if delta.get("content"):
                            yield {"type": "token", "content": delta["content"]}

                        for tc_delta in delta.get("tool_calls") or []:
                            idx = str(tc_delta.get("index", 0))
                            if idx not in tool_call_buffer:
                                tool_call_buffer[idx] = {"id": "", "name": "", "arguments": ""}
                            buf = tool_call_buffer[idx]
                            buf["id"] = buf["id"] or tc_delta.get("id", f"cloud_call_{idx}")
                            fn = tc_delta.get("function", {})
                            buf["name"] += fn.get("name", "")
                            buf["arguments"] += fn.get("arguments", "")

                        if choice.get("finish_reason"):
                            break

        if tool_call_buffer:
            yield {"type": "tool_calls", "calls": list(tool_call_buffer.values())}

        yield {"type": "done"}

    except httpx.ConnectError:
        yield {"type": "error", "message": "Cannot reach HyprCandy cloud. Check your internet connection."}
    except Exception as exc:
        yield {"type": "error", "message": f"Cloud stream error: {exc}"}
