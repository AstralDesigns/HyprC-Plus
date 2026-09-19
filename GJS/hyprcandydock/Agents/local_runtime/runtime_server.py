import asyncio
import json
import os
import time
import uuid
from pathlib import Path
from typing import Any, Optional

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel

import llama_manager
from agent_loop import local_backend, run_agentic_turn
from cloud_client import CLOUD_MODELS, stream_cloud, validate_license
from byok_client import stream_byok, PROVIDERS, get_provider_models, fetch_remote_models
from tools import TOOLS_SCHEMA

# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(title="HyprCandy Local Runtime", version="1.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── In-memory license cache ───────────────────────────────────────────────────
_cached_license_key: Optional[str] = None
_license_valid: Optional[bool] = None

# ── In-memory BYOK key store: provider -> api_key ─────────────────────────────
_byok_keys: dict[str, str] = {}
_byok_active_provider: Optional[str] = None

# ── In-memory download task registry ─────────────────────────────────────────
# task_id -> {percent, text, done, error, path, filename}
_download_tasks: dict[str, dict] = {}

# ── In-memory chat task registry ─────────────────────────────────────────────
# task_id -> {events: list[dict], done: bool, error: str|None, created_at: float}
_chat_tasks: dict[str, dict] = {}

# Max age for completed chat tasks before GC (30 minutes)
_CHAT_TASK_MAX_AGE_S = 1800


def _gc_chat_tasks():
    """Remove completed chat tasks older than MAX_AGE to prevent memory leaks."""
    now = time.time()
    stale = [
        tid for tid, t in _chat_tasks.items()
        if t.get("done") and (now - t.get("created_at", now)) > _CHAT_TASK_MAX_AGE_S
    ]
    for tid in stale:
        del _chat_tasks[tid]


# ── Pydantic models ───────────────────────────────────────────────────────────

class PullRequest(BaseModel):
    url: str
    filename: Optional[str] = None


class ImportRequest(BaseModel):
    path: str


class DeleteModelRequest(BaseModel):
    path: str


class ServerStartRequest(BaseModel):
    model_path: str
    ctx_size: int = 0
    max_tokens: int = 2048


class ChatRequest(BaseModel):
    messages: list[dict]
    project_context: Optional[str] = None
    # Inference mode preference: 'local' | 'byok' | 'cloud'
    inference_mode: Optional[str] = None
    # Cloud (Vercel gateway) only:
    model_choice: Optional[str] = None
    license_key: Optional[str] = None
    # BYOK fields:
    byok_provider: Optional[str] = None
    byok_key: Optional[str] = None
    byok_model: Optional[str] = None


class LicenseRequest(BaseModel):
    key: str


class SecretRequest(BaseModel):
    key: str


class BYOKSetRequest(BaseModel):
    provider: str
    api_key: str
    set_active: bool = True


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "server": "hyprcandy-runtime"}


# ── Model catalog ─────────────────────────────────────────────────────────────

@app.get("/api/models")
async def get_models():
    return {"models": llama_manager.list_models()}


@app.get("/api/models/search")
async def search_models(q: str = ""):
    """Search public Hugging Face GGUF repositories from the native runtime."""
    query = q.strip()
    if not query:
        return {"models": []}
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                "https://huggingface.co/api/models",
                params={"search": query, "filter": "gguf", "sort": "downloads", "direction": "-1", "limit": 15},
            )
            response.raise_for_status()
            rows = response.json()
        return {"models": [
            {
                "id": row.get("id") or row.get("modelId"),
                "downloads": row.get("downloads"),
                "likes": row.get("likes"),
                "tags": row.get("tags") or [],
            }
            for row in rows
            if isinstance(row, dict) and (row.get("id") or row.get("modelId"))
        ][:15]}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Hugging Face search failed: {exc}")


@app.get("/api/models/inspect")
async def inspect_model(repo: str = ""):
    """Return files available in a Hugging Face repository."""
    import re
    safe_repo = repo.strip()
    if not re.match(r"^[^/]+/[^/]+$", safe_repo):
        raise HTTPException(status_code=400, detail="Invalid Hugging Face repository; expected owner/name")
    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.get(f"https://huggingface.co/api/models/{safe_repo}", params={"full": "true"})
            response.raise_for_status()
            metadata = response.json()
        files = [item.get("rfilename") for item in metadata.get("siblings", []) if isinstance(item, dict) and item.get("rfilename")]
        return {"repo": safe_repo, "files": files}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Hugging Face inspection failed: {exc}")


@app.post("/api/models/pull/start")
async def pull_model_start(req: PullRequest):
    """Start a background GGUF download. Returns {task_id} immediately."""
    task_id = str(uuid.uuid4())
    _download_tasks[task_id] = {"percent": 0, "text": "Starting download…", "done": False, "error": None}

    async def _run():
        try:
            async for progress in llama_manager.download_model(req.url, req.filename):
                _download_tasks[task_id].update({
                    "percent": progress.get("percent", 0),
                    "text": progress.get("text", ""),
                    "done": progress.get("done", False),
                    "path": progress.get("path"),
                    "filename": progress.get("filename"),
                    "error": None,
                })
                if progress.get("done"):
                    break
        except Exception as exc:
            _download_tasks[task_id].update({"done": True, "error": str(exc)})

    asyncio.create_task(_run())
    return {"task_id": task_id}


@app.get("/api/models/pull/status/{task_id}")
async def pull_model_status(task_id: str):
    """Poll download progress for a given task_id."""
    if task_id not in _download_tasks:
        raise HTTPException(status_code=404, detail="Unknown task_id")
    return _download_tasks[task_id]


@app.post("/api/models/pull")
async def pull_model_legacy(req: PullRequest):
    """Legacy SSE endpoint — use /pull/start + /pull/status instead."""
    return await pull_model_start(req)


@app.post("/api/models/import")
async def import_model(req: ImportRequest):
    try:
        result = llama_manager.import_model(req.path)
        return result
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/api/models/delete")
async def delete_model(req: DeleteModelRequest):
    try:
        result = await llama_manager.delete_model(req.path)
        return result
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/api/models/clear")
async def clear_models():
    try:
        result = await llama_manager.clear_all_models()
        return result
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ── llama-server lifecycle ────────────────────────────────────────────────────

@app.post("/api/server/start")
async def start_server(req: ServerStartRequest):
    try:
        status = await llama_manager.start_server(req.model_path, req.ctx_size, req.max_tokens)
        return status
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/api/server/stop")
async def stop_server():
    return await llama_manager.stop_server()


@app.get("/api/server/status")
async def server_status():
    return llama_manager.server_status()


# ── Chat (agentic loop) ───────────────────────────────────────────────────────

@app.post("/api/chat/start")
async def chat_start(req: ChatRequest):
    """
    Start a background agentic chat turn.
    Returns {task_id} immediately. Poll /api/chat/poll/{task_id}?since=N for events.

    Routing priority:
      1. byok_provider + byok_key → BYOK provider (Google/OpenAI/Anthropic/xAI)
      2. license_key → Vercel AI Gateway (managed cloud)
      3. fallback → local llama-server
    """
    # GC stale tasks first
    _gc_chat_tasks()

    task_id = str(uuid.uuid4())
    _chat_tasks[task_id] = {
        "events": [],
        "done": False,
        "error": None,
        "cancelled": False,
        "created_at": time.time(),
        "task": None,
    }

    # Determine route based on explicit inference_mode preference and available credentials
    inference_mode = req.inference_mode
    byok_provider = req.byok_provider or _byok_active_provider
    byok_key = req.byok_key or _byok_keys.get(byok_provider or "", "")
    byok_model = req.byok_model

    if inference_mode == "local":
        endpoint = "local"
    elif inference_mode == "byok":
        endpoint = "byok" if (byok_provider and byok_key) else "local"
    elif byok_provider and byok_key:
        endpoint = "byok"
    elif req.license_key or _cached_license_key:
        endpoint = "cloud"
    else:
        endpoint = "local"

    async def _run():
        try:
            if endpoint == "local":
                if not await llama_manager.health_check():
                    _chat_tasks[task_id]["events"].append(
                        {"type": "error", "data": {"message": "llama-server not running. Load a model first."}}
                    )
                    return
                backend_fn = local_backend

            elif endpoint == "byok":
                provider = byok_provider
                default_model = "openrouter/free" if provider == "openrouter" else PROVIDERS.get(provider, {}).get("models", [{}])[0].get("id", "")
                model = byok_model or default_model
                key = byok_key

                async def backend_fn(messages):
                    async for event in stream_byok(messages, provider, model, key, TOOLS_SCHEMA):
                        yield event

            else:  # cloud (Vercel)
                key = req.license_key or _cached_license_key
                model = req.model_choice or CLOUD_MODELS[0]["id"]

                async def backend_fn(messages):
                    async for event in stream_cloud(messages, model, key):
                        yield event

            async for event in run_agentic_turn(
                user_message=_last_user_message(req.messages),
                history=_history_without_last(req.messages),
                backend_fn=backend_fn,
                project_context=req.project_context,
            ):
                _chat_tasks[task_id]["events"].append(event)
                if event.get("type") in ("done", "error"):
                    break

        except asyncio.CancelledError:
            _chat_tasks[task_id]["events"].append(
                {"type": "error", "data": {"message": "Generation cancelled"}}
            )
        except Exception as exc:
            _chat_tasks[task_id]["events"].append(
                {"type": "error", "data": {"message": str(exc)}}
            )
        finally:
            _chat_tasks[task_id]["done"] = True

    _chat_tasks[task_id]["task"] = asyncio.create_task(_run())
    return {"task_id": task_id, "endpoint": endpoint}


@app.get("/api/chat/poll/{task_id}")
async def chat_poll(task_id: str, since: int = 0):
    """
    Return all events accumulated since index `since`.
    Response: {events: [...], done: bool, total: int}
    """
    if task_id not in _chat_tasks:
        raise HTTPException(status_code=404, detail="Unknown chat task_id")
    task = _chat_tasks[task_id]
    new_events = task["events"][since:]
    return {
        "events": new_events,
        "done": task["done"],
        "total": len(task["events"]),
    }


@app.post("/api/chat/cancel/{task_id}")
async def chat_cancel(task_id: str):
    """Cancel a running chat task and release the llama-server request."""
    task = _chat_tasks.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Unknown chat task_id")
    if task.get("done"):
        return {"cancelled": False, "done": True}
    task["cancelled"] = True
    running = task.get("task")
    if running and not running.done():
        running.cancel()
    return {"cancelled": True, "task_id": task_id}


# Legacy SSE endpoints kept for compatibility — use /chat/start + /chat/poll instead
@app.post("/api/chat/local")
async def chat_local(req: ChatRequest):
    return await chat_start(req)


@app.post("/api/chat/cloud")
async def chat_cloud(req: ChatRequest):
    return await chat_start(req)


# ── BYOK provider management ──────────────────────────────────────────────────

@app.post("/api/byok/set")
async def byok_set(req: BYOKSetRequest):
    """Save a BYOK API key for a provider. Optionally set as active."""
    global _byok_active_provider
    if req.provider not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"Unknown provider: {req.provider}")
    _byok_keys[req.provider] = req.api_key
    if req.set_active:
        _byok_active_provider = req.provider
    return {"ok": True, "active_provider": _byok_active_provider}


@app.get("/api/byok/status")
async def byok_status():
    """Return configured providers and active provider."""
    result = {}
    for provider in PROVIDERS:
        key = _byok_keys.get(provider, "")
        result[provider] = {
            "configured": bool(key),
            "key_preview": key[:8] + "…" if key else "",
            "active": _byok_active_provider == provider,
            "models": get_provider_models(provider),
        }
    return {"providers": result, "active_provider": _byok_active_provider}


@app.get("/api/byok/models/{provider}")
async def byok_models(provider: str, api_key: Optional[str] = None):
    """Return available models for a BYOK provider, dynamically fetched if possible."""
    if provider not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")
    key = api_key or _byok_keys.get(provider, "")
    models = await fetch_remote_models(provider, key)
    fallback = get_provider_models(provider)
    is_live = (models != fallback)
    return {"provider": provider, "models": models, "live": is_live}


@app.get("/api/byok/key/{provider}")
async def byok_get_key(provider: str):
    """Return the saved key for a provider (for client reveal/restore)."""
    if provider not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")
    key = _byok_keys.get(provider, "")
    return {"provider": provider, "key": key}


@app.post("/api/byok/activate/{provider}")
async def byok_activate(provider: str):
    """Set a configured provider as active."""
    global _byok_active_provider
    if provider not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")
    _byok_active_provider = provider
    return {"ok": True, "active_provider": _byok_active_provider}


@app.post("/api/byok/deactivate")
async def byok_deactivate():
    """Deactivate any active BYOK cloud provider."""
    global _byok_active_provider
    _byok_active_provider = None
    return {"ok": True, "active_provider": None}


@app.delete("/api/byok/revoke/{provider}")
async def byok_revoke(provider: str):
    """Remove saved key for a provider."""
    global _byok_active_provider
    _byok_keys.pop(provider, None)
    if _byok_active_provider == provider:
        _byok_active_provider = None
    return {"ok": True}


# ── License (Vercel managed cloud) ───────────────────────────────────────────

@app.post("/api/license/validate")
async def validate_license_endpoint(req: LicenseRequest):
    global _cached_license_key, _license_valid
    result = await validate_license(req.key)
    if result.get("valid"):
        _cached_license_key = req.key
        _license_valid = True
    else:
        _license_valid = False
    return result


@app.get("/api/license/status")
async def license_status():
    if _cached_license_key and _license_valid:
        return {"valid": True, "key_preview": _cached_license_key[:8] + "…"}
    return {"valid": False}


# ── Cloud models list ─────────────────────────────────────────────────────────

@app.get("/api/cloud/models")
async def cloud_models():
    return {"models": CLOUD_MODELS}


# ── Secret store relay ────────────────────────────────────────────────────────

@app.post("/api/secret/set")
async def secret_set(req: SecretRequest):
    global _cached_license_key
    _cached_license_key = req.key
    return {"ok": True}


@app.get("/api/secret/get")
async def secret_get():
    return {"key": _cached_license_key or ""}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _last_user_message(messages: list[dict]) -> str:
    for m in reversed(messages):
        if m.get("role") == "user":
            return m.get("content", "")
    return ""


def _history_without_last(messages: list[dict]) -> list[dict]:
    """Return all messages except the last user turn (which run_agentic_turn appends itself)."""
    for i in range(len(messages) - 1, -1, -1):
        if messages[i].get("role") == "user":
            return messages[:i]
    return messages
