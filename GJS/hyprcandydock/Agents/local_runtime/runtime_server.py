import asyncio
import json
import os
import subprocess
import time
import html
import re
import urllib.parse
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel

from agent_loop import run_agentic_turn
from cloud_client import CLOUD_MODELS, stream_cloud, validate_license
from byok_client import stream_byok, PROVIDERS, get_provider_models, fetch_remote_models, complete_byok
from tools import TOOLS_SCHEMA
import tools as tools_module

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

# ── Gumroad Agents license verification ───────────────────────────────────────
# Verified server-side (httpx) so the embedded WebEngine never trips Gumroad's
# CORS. product_id is the Gumroad permalink; swap for the numeric id if needed.
GUMROAD_VERIFY_URL = "https://api.gumroad.com/v2/licenses/verify"
# Gumroad's verify API keys the license to a specific product_id. The checkout
# permalink works only if it is the exact product id Gumroad expects; override
# with the real product id via HYPRCANDY_GUMROAD_PRODUCT_ID if verification
# keeps returning "license does not exist for the provided product."
GUMROAD_PRODUCT_ID = os.environ.get("HYPRCANDY_GUMROAD_PRODUCT_ID", "FPyBDGtwIdoMHQQKPo89ZQ==")

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
    # Spec-driven (plan-before-execute) mode + project root for the verification gate:
    spec_enabled: Optional[bool] = None
    project_path: Optional[str] = None
    # Client-generated id grouping this turn's file edits for "Revert this turn"
    # (plan §3.7). Falls back to the server task_id when omitted.
    turn_id: Optional[str] = None
    ai_settings: Optional[dict] = None


class OllamaPullRequest(BaseModel):
    model: str


class OllamaDeleteRequest(BaseModel):
    model: str


class AISettingsRequest(BaseModel):
    openrouter: Optional[dict] = None
    ollama: Optional[dict] = None


class LicenseRequest(BaseModel):
    key: str


class SecretRequest(BaseModel):
    key: str


class BYOKSetRequest(BaseModel):
    provider: str
    api_key: str
    set_active: bool = True


class LicenseVerifyRequest(BaseModel):
    license_key: str


class CompletionRequest(BaseModel):
    provider: str
    api_key: Optional[str] = None
    model: Optional[str] = None
    prompt: str
    max_tokens: Optional[int] = 64
    stop: Optional[list[str]] = None


class SteerRequest(BaseModel):
    text: str


class ApprovalRequest(BaseModel):
    # 'approve' → execute the drafted spec; 'revise' → re-draft with feedback
    # text (delivered through the steering queue); 'cancel' → abort the turn.
    action: str
    text: Optional[str] = None


class MemoryDeleteRequest(BaseModel):
    topic: str


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "server": "hyprcandy-runtime"}


# ── AI Settings & Ollama State ───────────────────────────────────────────────
AI_SETTINGS_FILE = os.path.expanduser("~/.config/hyprcandy/ai_settings.json")
_DEFAULT_AI_SETTINGS: dict[str, Any] = {
    "openrouter": {
        "temperature": 0.2,
        "reasoning_effort": "high",
        "reasoning_tokens": 16384,
        "max_tokens": 16384,
        "top_p": 1.0,
    },
    "ollama": {
        "host": "http://localhost:11434",
        "temperature": 0.2,
        "num_ctx": 32768,
        "max_tokens": 8192,
        "top_p": 0.9,
    },
}

_ai_settings: dict[str, Any] = json.loads(json.dumps(_DEFAULT_AI_SETTINGS))
try:
    if os.path.isfile(AI_SETTINGS_FILE):
        with open(AI_SETTINGS_FILE, "r", encoding="utf-8") as f:
            loaded = json.load(f)
            if isinstance(loaded, dict):
                if "openrouter" in loaded and isinstance(loaded["openrouter"], dict):
                    _ai_settings["openrouter"].update(loaded["openrouter"])
                if "ollama" in loaded and isinstance(loaded["ollama"], dict):
                    _ai_settings["ollama"].update(loaded["ollama"])
except Exception as e:
    logger.warning("Failed to load ai_settings.json: %s", e)

def _save_ai_settings():
    try:
        os.makedirs(os.path.dirname(AI_SETTINGS_FILE), exist_ok=True)
        with open(AI_SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump(_ai_settings, f, indent=2)
    except Exception as e:
        logger.error("Failed to save ai_settings.json: %s", e)

_ollama_pull_tasks: dict[str, dict] = {}
_ollama_library_cache: list[dict] = []
_ollama_library_cache_time: float = 0
OLLAMA_SERVICE_SCRIPT = os.path.expanduser("~/.config/quickshell/bar/scripts/ollama-service.sh")

def _get_offline_ollama_models() -> list[dict]:
    """Scan local ~/.ollama/models/manifests directly from disk if daemon is offline."""
    results = []
    manifests_dir = os.path.expanduser("~/.ollama/models/manifests")
    if not os.path.isdir(manifests_dir):
        return results
    try:
        for reg in os.listdir(manifests_dir):
            reg_dir = os.path.join(manifests_dir, reg)
            if not os.path.isdir(reg_dir):
                continue
            for ns in os.listdir(reg_dir):
                ns_dir = os.path.join(reg_dir, ns)
                if not os.path.isdir(ns_dir):
                    continue
                for mname in os.listdir(ns_dir):
                    m_dir = os.path.join(ns_dir, mname)
                    if not os.path.isdir(m_dir):
                        continue
                    for tag in os.listdir(m_dir):
                        tag_path = os.path.join(m_dir, tag)
                        if not os.path.isfile(tag_path):
                            continue
                        full_name = f"{mname}:{tag}" if ns == "library" else f"{ns}/{mname}:{tag}"
                        stat = os.stat(tag_path)
                        size = 0
                        try:
                            with open(tag_path, "r", encoding="utf-8") as mf:
                                mdata = json.load(mf)
                                layers = mdata.get("layers", [])
                                size = sum(l.get("size", 0) for l in layers)
                        except Exception:
                            pass
                        results.append({
                            "name": full_name,
                            "model": full_name,
                            "modified_at": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                            "size": size,
                            "details": {"family": mname},
                        })
    except Exception as e:
        logger.warning("Error reading offline ollama manifests: %s", e)
    return results

def _parse_ollama_html(html_text: str) -> list[dict]:
    items = []
    seen = set()
    for full_match in re.finditer(r'<a href=\"/library/([^\"]+)\"(.*?)</a>', html_text, re.DOTALL):
        mid = full_match.group(1).strip()
        if mid in seen:
            continue
        seen.add(mid)
        body = full_match.group(2)
        t_m = re.search(r'<span[^>]*>([^<]+)</span>', body)
        name = t_m.group(1).strip() if t_m else mid
        p_m = re.search(r'<p[^>]*>([^<]+)</p>', body)
        desc = html.unescape(p_m.group(1).strip()) if p_m else ""
        tags = re.findall(r'<span[^>]*text-indigo-600[^>]*>([^<]+)</span>', body)
        items.append({"id": mid, "name": name, "desc": desc, "tags": tags})
    return items

# ── Ollama REST APIs ──────────────────────────────────────────────────────────

@app.post("/api/ollama/service/{action}")
async def ollama_service_action(action: str):
    if action not in ("start", "stop", "toggle", "status"):
        raise HTTPException(status_code=400, detail="Invalid action")
    try:
        proc = await asyncio.create_subprocess_exec(
            OLLAMA_SERVICE_SCRIPT, action,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate()
        status_text = stdout.decode().strip()
        return {"status": status_text, "returncode": proc.returncode}
    except Exception as e:
        return {"status": "error", "error": str(e)}

@app.get("/api/ollama/status")
async def ollama_status():
    host = _ai_settings.get("ollama", {}).get("host", "http://127.0.0.1:11434")
    if "localhost" in host:
        host = host.replace("localhost", "127.0.0.1")
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            resp = await client.get(f"{host.rstrip('/')}/api/version")
            if resp.status_code == 200:
                data = resp.json()
                return {"online": True, "version": data.get("version", "unknown"), "host": host}
    except Exception:
        pass
    return {"online": False, "version": None, "host": host, "error": "Ollama service is not running"}

@app.get("/api/ollama/models")
async def ollama_models():
    host = _ai_settings.get("ollama", {}).get("host", "http://127.0.0.1:11434")
    if "localhost" in host:
        host = host.replace("localhost", "127.0.0.1")
    live_models: list[dict] = []
    try:
        async with httpx.AsyncClient(timeout=4.0) as client:
            resp = await client.get(f"{host.rstrip('/')}/api/tags")
            if resp.status_code == 200:
                data = resp.json()
                live_models = data.get("models", [])
    except Exception:
        pass

    if live_models:
        return {"models": live_models}

    # Fallback to local on-disk manifest scan
    offline = _get_offline_ollama_models()
    return {"models": offline}

@app.get("/api/ollama/library")
async def ollama_library(q: str = ""):
    global _ollama_library_cache, _ollama_library_cache_time
    cleaned_q = (q or "").strip()
    now = time.time()

    if cleaned_q:
        try:
            url = f"https://ollama.com/search?q={urllib.parse.quote(cleaned_q)}"
            async with httpx.AsyncClient(timeout=8.0, headers={"User-Agent": "Mozilla/5.0"}) as client:
                resp = await client.get(url)
                if resp.status_code == 200:
                    models = _parse_ollama_html(resp.text)
                    if models:
                        return {"models": models}
        except Exception as e:
            logger.warning("Failed to search ollama.com: %s", e)
        if _ollama_library_cache:
            filtered = [
                m for m in _ollama_library_cache
                if cleaned_q.lower() in m["id"].lower()
                or cleaned_q.lower() in m["name"].lower()
                or cleaned_q.lower() in m.get("desc", "").lower()
                or any(cleaned_q.lower() in t.lower() for t in m.get("tags", []))
            ]
            return {"models": filtered}
        return {"models": []}

    if _ollama_library_cache and (now - _ollama_library_cache_time < 3600):
        return {"models": _ollama_library_cache}

    try:
        url = "https://ollama.com/library"
        async with httpx.AsyncClient(timeout=10.0, headers={"User-Agent": "Mozilla/5.0"}) as client:
            resp = await client.get(url)
            if resp.status_code == 200:
                models = _parse_ollama_html(resp.text)
                if models:
                    _ollama_library_cache = models
                    _ollama_library_cache_time = now
                    return {"models": _ollama_library_cache}
    except Exception as e:
        logger.warning("Failed to fetch ollama.com/library: %s", e)

    return {"models": _ollama_library_cache}

@app.post("/api/ollama/pull")
async def ollama_pull(req: OllamaPullRequest):
    host = _ai_settings.get("ollama", {}).get("host", "http://localhost:11434")
    model_name = req.model.strip()
    if not model_name:
        raise HTTPException(status_code=400, detail="Model name required")
    task_id = str(uuid.uuid4())
    _ollama_pull_tasks[task_id] = {
        "model": model_name,
        "done": False,
        "percent": 0,
        "status": "Starting download...",
        "error": None,
    }

    async def _do_pull():
        try:
            async with httpx.AsyncClient(timeout=3600.0) as client:
                async with client.stream("POST", f"{host.rstrip('/')}/api/pull", json={"model": model_name}) as resp:
                    if not resp.is_success:
                        _ollama_pull_tasks[task_id]["error"] = f"HTTP {resp.status_code}"
                        _ollama_pull_tasks[task_id]["done"] = True
                        return
                    async for line in resp.aiter_lines():
                        if not line:
                            continue
                        try:
                            chunk = json.loads(line)
                            status_text = chunk.get("status", "")
                            completed = chunk.get("completed", 0)
                            total = chunk.get("total", 0)
                            percent = int((completed / total) * 100) if total > 0 else 0
                            _ollama_pull_tasks[task_id]["status"] = status_text
                            _ollama_pull_tasks[task_id]["percent"] = percent
                            if chunk.get("error"):
                                _ollama_pull_tasks[task_id]["error"] = chunk["error"]
                        except Exception:
                            pass
            _ollama_pull_tasks[task_id]["done"] = True
            _ollama_pull_tasks[task_id]["status"] = "Complete"
            _ollama_pull_tasks[task_id]["percent"] = 100
        except Exception as e:
            _ollama_pull_tasks[task_id]["error"] = str(e)
            _ollama_pull_tasks[task_id]["done"] = True

    asyncio.create_task(_do_pull())
    return {"task_id": task_id}

@app.get("/api/ollama/pull/status/{task_id}")
async def ollama_pull_status(task_id: str):
    info = _ollama_pull_tasks.get(task_id)
    if not info:
        return {"done": True, "percent": 0, "status": "Not found", "error": "Task not found"}
    return info

@app.post("/api/ollama/delete")
async def ollama_delete(req: OllamaDeleteRequest):
    host = _ai_settings.get("ollama", {}).get("host", "http://localhost:11434")
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.request("DELETE", f"{host.rstrip('/')}/api/delete", json={"model": req.model})
            if resp.status_code in (200, 204):
                return {"status": "ok"}
            return {"status": "error", "error": f"HTTP {resp.status_code}"}
    except Exception as e:
        return {"status": "error", "error": str(e)}

@app.get("/api/settings/ai")
async def get_ai_settings():
    return _ai_settings

@app.post("/api/settings/ai")
async def update_ai_settings(req: AISettingsRequest):
    if req.openrouter is not None:
        _ai_settings["openrouter"].update(req.openrouter)
    if req.ollama is not None:
        _ai_settings["ollama"].update(req.ollama)
    _save_ai_settings()
    return _ai_settings

@app.get("/api/models")
async def get_models():
    return {"models": []}


@app.post("/api/models/pull/start")
async def pull_model_start(req: PullRequest):
    return {"task_id": "noop", "status": "disabled"}


@app.get("/api/models/pull/status/{task_id}")
async def pull_model_status(task_id: str):
    return {"done": True, "percent": 100, "text": "Local models disabled"}


@app.post("/api/models/pull")
async def pull_model_legacy(req: PullRequest):
    return {"task_id": "noop", "status": "disabled"}


@app.post("/api/models/import")
async def import_model(req: ImportRequest):
    return {"status": "disabled"}


@app.post("/api/models/delete")
async def delete_model(req: DeleteModelRequest):
    return {"status": "ok"}


@app.post("/api/models/clear")
async def clear_models():
    return {"status": "ok"}


# ── Legacy llama-server lifecycle (no-ops) ─────────────────────────────────

@app.post("/api/server/start")
async def start_server(req: ServerStartRequest):
    return {"running": False, "status": "disabled"}


@app.post("/api/server/stop")
async def stop_server():
    return {"running": False, "status": "disabled"}


@app.get("/api/server/status")
async def server_status():
    return {"running": False, "status": "disabled"}


# ── Chat (agentic loop) ───────────────────────────────────────────────────────

@app.post("/api/chat/start")
async def chat_start(req: ChatRequest):
    """
    Start a background agentic chat turn.
    Returns {task_id} immediately. Poll /api/chat/poll/{task_id}?since=N for events.

    Routing priority:
      1. byok_provider + byok_key → BYOK provider (Google/OpenAI/Anthropic/xAI)
      2. license_key → Vercel AI Gateway (managed cloud)
      3. otherwise → BYOK with OpenRouter (free-tier route) as last resort

    NOTE: there is deliberately no local (llama-server/GGUF/WebLLM) branch —
    local inference was fully removed from the product (2026-10; see agent-app
    plan §8.2 findings). Inference is BYOK or managed cloud only.
    """
    # GC stale tasks first
    _gc_chat_tasks()

    task_id = str(uuid.uuid4())
    turn_id = (req.turn_id or task_id).strip() or task_id
    _chat_tasks[task_id] = {
        "events": [],
        "done": False,
        "error": None,
        "created_at": time.time(),
        "task": None,       # asyncio.Task, set below once created
        "cancelled": False,
        "turn_id": turn_id,            # groups this turn's write_file edits for revert
        "pending_instructions": [],  # steering text queued mid-run, drained per-iteration
        "approval": None,            # spec-driven gate: 'approve' | 'revise' | 'cancel'
    }

    # Determine route based on explicit inference_mode preference and available credentials
    inference_mode = req.inference_mode
    byok_provider = req.byok_provider or _byok_active_provider
    byok_key = req.byok_key or _byok_keys.get(byok_provider or "", "")
    byok_model = req.byok_model

    if inference_mode == "byok" or (byok_provider and (byok_key or byok_provider in ("openrouter", "ollama"))):
        endpoint = "byok"
    elif inference_mode == "cloud" or (req.license_key or _cached_license_key):
        endpoint = "cloud"
    else:
        endpoint = "byok"

    async def _run():
        # Tag every write_file in this turn (isolated per asyncio task via the
        # context var) so a later /api/turns/revert can roll the whole turn back.
        tools_module.CURRENT_TURN_ID.set(turn_id)
        try:
            if endpoint == "byok":
                provider = byok_provider or "openrouter"
                default_model = "openrouter/free" if provider == "openrouter" else PROVIDERS.get(provider, {}).get("models", [{}])[0].get("id", "")
                model = byok_model or default_model
                key = byok_key

                if not key and provider not in ("openrouter", "ollama"):
                    _chat_tasks[task_id]["events"].append(
                        {"type": "error", "data": {"message": f"Please configure your API key for {provider} in the Model Manager."}}
                    )
                    return

                effective_settings = dict(_ai_settings)
                if req.ai_settings and isinstance(req.ai_settings, dict):
                    if "openrouter" in req.ai_settings:
                        effective_settings.setdefault("openrouter", {}).update(req.ai_settings["openrouter"])
                    if "ollama" in req.ai_settings:
                        effective_settings.setdefault("ollama", {}).update(req.ai_settings["ollama"])

                async def backend_fn(messages):
                    async for event in stream_byok(messages, provider, model, key, TOOLS_SCHEMA, ai_settings=effective_settings):
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
                steer_source=lambda: _drain_steers(task_id),
                spec_enabled=bool(req.spec_enabled),
                project_path=req.project_path,
                approve_source=lambda: _read_approval(task_id),
            ):
                _chat_tasks[task_id]["events"].append(event)
                if event.get("type") in ("done", "error"):
                    break

        except asyncio.CancelledError:
            # Client aborted (Stop button / new message superseding this one).
            # Don't resurrect the task — just record that it ended, so a
            # stale poll doesn't hang waiting for a 'done' event that will
            # never come from run_agentic_turn's normal exit paths.
            _chat_tasks[task_id]["cancelled"] = True
            _chat_tasks[task_id]["events"].append(
                {"type": "error", "data": {"message": "Cancelled."}}
            )
            raise
        except Exception as exc:
            _chat_tasks[task_id]["events"].append(
                {"type": "error", "data": {"message": str(exc)}}
            )
        finally:
            _chat_tasks[task_id]["done"] = True

    task = asyncio.create_task(_run())
    _chat_tasks[task_id]["task"] = task
    return {"task_id": task_id, "endpoint": endpoint}


@app.post("/api/chat/cancel/{task_id}")
async def chat_cancel(task_id: str):
    """
    Cancel an in-flight chat turn. Cancels the backing asyncio.Task, which
    unwinds run_agentic_turn and closes the underlying HTTP stream to the
    model provider (dropping the connection makes the provider stop
    generating for that request instead of burning tokens/CPU for a client
    that has already given up).
    """
    task_entry = _chat_tasks.get(task_id)
    if not task_entry:
        raise HTTPException(status_code=404, detail="Unknown chat task_id")
    if task_entry.get("done"):
        return {"ok": True, "already_done": True}
    task: Optional[asyncio.Task] = task_entry.get("task")
    if task and not task.done():
        task.cancel()
    task_entry["cancelled"] = True
    return {"ok": True, "already_done": False}


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


@app.post("/api/chat/steer/{task_id}")
async def chat_steer(task_id: str, req: SteerRequest):
    """
    Inject a steering instruction into an in-flight chat turn.

    The text is queued and drained by run_agentic_turn at the next iteration
    boundary (see agent_loop.steer_source). Returns {ok: false, done: true} if
    the task already finished/cancelled so the client can fall back to a normal
    new-message send.
    """
    task_entry = _chat_tasks.get(task_id)
    if not task_entry:
        raise HTTPException(status_code=404, detail="Unknown chat task_id")
    if task_entry.get("done") or task_entry.get("cancelled"):
        return {"ok": False, "done": True}
    text = (req.text or "").strip()
    if not text:
        return {"ok": False, "done": False}
    task_entry.setdefault("pending_instructions", []).append(text)
    return {"ok": True, "done": False}


@app.post("/api/chat/approve/{task_id}")
async def chat_approve(task_id: str, req: ApprovalRequest):
    """
    Resolve an `awaiting_approval` gate from the spec-driven mode.

    'approve' resumes execution of the drafted plan; 'revise' re-drafts the plan
    using `text` (queued through the same steering path so the loop folds it in
    as revision notes); 'cancel' aborts the turn. Returns {ok:false, done:true}
    if the task already finished.
    """
    task_entry = _chat_tasks.get(task_id)
    if not task_entry:
        raise HTTPException(status_code=404, detail="Unknown chat task_id")
    if task_entry.get("done") or task_entry.get("cancelled"):
        return {"ok": False, "done": True}
    action = (req.action or "").strip().lower()
    if action not in ("approve", "revise", "cancel"):
        return {"ok": False, "done": False}
    if action == "revise" and req.text and req.text.strip():
        task_entry.setdefault("pending_instructions", []).append(req.text.strip())
    task_entry["approval"] = action
    return {"ok": True, "done": False}


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


@app.post("/api/byok/complete")
async def byok_complete(req: CompletionRequest):
    """Single non-streaming inline completion (Monaco ghost text).

    Reads the saved key for the provider; never persists anything. Returns
    { text } (possibly empty). Errors surface as HTTP 4xx/5xx which the client
    swallows so a failed completion is simply no suggestion.
    """
    if req.provider not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"Unknown provider: {req.provider}")
    # Prefer the key riding in the request (survives server restarts, matching
    # the chat path); fall back to whatever was saved in-memory.
    key = (req.api_key or "").strip() or _byok_keys.get(req.provider, "")
    if not key and req.provider != "ollama":
        raise HTTPException(status_code=400, detail=f"No API key saved for {req.provider}")
    if req.provider == "ollama" and not key:
        key = "ollama"
    try:
        text = await complete_byok(
            req.provider,
            req.model or "",
            key,
            req.prompt,
            max_tokens=req.max_tokens or 64,
            stop=req.stop or None,
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=str(exc))
    return {"text": text}


@app.post("/api/license/verify")
async def license_verify(req: LicenseVerifyRequest):
    """Verify a Gumroad Agents license key server-side (avoids browser CORS)."""
    key = (req.license_key or "").strip()
    if not key:
        return {"ok": False, "reason": "Enter a license key first."}
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                GUMROAD_VERIFY_URL,
                data={"product_id": GUMROAD_PRODUCT_ID, "license_key": key},
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
            data = resp.json()
    except Exception as exc:
        return {"ok": False, "reason": f"Could not reach Gumroad: {exc}"}
    if data.get("success"):
        sale = data.get("sale") or {}
        email = sale.get("formatted_email") or sale.get("email") or data.get("email") or ""
        # The Agents product is a recurring subscription: Gumroad keeps returning
        # success:true for a cancelled key until it fully lapses, and signals the
        # paid-up state separately via `active` (+ `expires_at`). The frontend
        # grace logic keys off `active`, so surface it. Default active to True
        # only when the field is entirely absent (non-subscription/legacy).
        has_active = "active" in data
        return {
            "ok": True,
            "active": bool(data.get("active")) if has_active else True,
            "expires_at": data.get("expires_at"),
            "email": email,
        }
    return {"ok": False, "active": False, "expires_at": None, "reason": data.get("message") or "License key invalid or expired."}


# ── Pending file edits (write_file diff review) ──────────────────────────────
# write_file stages a pre-edit snapshot rather than requiring a second
# round-trip through the model to apply/undo a change. "Accept" just forgets
# the snapshot (the file is already correct on disk); "reject" restores it.

class PathBody(BaseModel):
    path: str


@app.get("/api/files/pending")
async def files_pending():
    return {"files": tools_module.list_pending_edits()}


@app.post("/api/files/accept")
async def files_accept(body: PathBody):
    ok = tools_module.accept_edit(body.path)
    return {"ok": ok}


@app.post("/api/files/reject")
async def files_reject(body: PathBody):
    ok = tools_module.reject_edit(body.path)
    return {"ok": ok}


@app.post("/api/files/accept-all")
async def files_accept_all():
    count = tools_module.accept_all_edits()
    return {"ok": True, "count": count}


@app.post("/api/files/reject-all")
async def files_reject_all():
    count = tools_module.reject_all_edits()
    return {"ok": True, "count": count}


# ── Turn revert (plan §3.7) ──────────────────────────────────────────────────
# Every write_file in a turn is tagged with the turn id (see CURRENT_TURN_ID),
# so the whole turn's file changes can be rolled back in one action.

class TurnBody(BaseModel):
    turn_id: str


@app.get("/api/turns/{turn_id}/edits")
async def turn_edits(turn_id: str):
    """List the files a turn touched (for a revert confirmation dialog)."""
    return {"files": tools_module.get_turn_edits(turn_id)}


@app.post("/api/turns/revert")
async def turn_revert(body: TurnBody):
    """Restore every file the turn touched to its pre-turn state."""
    return tools_module.revert_turn(body.turn_id)


# ── Agent memory (durable topic notes) ───────────────────────────────────────
# Backs the Memories panel; the same files the agent reads/writes via its
# list/read/save/delete_memory tools (see tools.MEMORY_DIR).

@app.get("/api/memories")
async def memories_list():
    return await tools_module.list_memories()


@app.post("/api/memories/delete")
async def memories_delete(body: MemoryDeleteRequest):
    return await tools_module.delete_memory(body.topic)


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


# ── Storage / block-device API ────────────────────────────────────────────────

class StorageMountRequest(BaseModel):
    device: str  # e.g. "sdc1"


def _lsblk_devices() -> list[dict]:
    """Return relevant block-device partitions from lsblk JSON output.

    Filters out loop, swap, and system-only partitions (/boot, /home, /,
    [SWAP], /var/tmp, etc.) so only user-facing drives appear in the UI.
    """
    try:
        result = subprocess.run(
            ["lsblk", "-J", "-o", "NAME,LABEL,FSTYPE,MOUNTPOINTS,MOUNTPOINT,SIZE,TYPE,HOTPLUG,PATH"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            return []
        data = json.loads(result.stdout)
    except Exception:
        return []

    SYSTEM_MOUNTS = {
        "/", "/boot", "/home", "/boot/efi", "/root", "/srv",
        "/var", "/var/tmp", "/var/log", "/var/cache", "/tmp", "[SWAP]"
    }

    devices: list[dict] = []
    for disk in data.get("blockdevices", []):
        if disk.get("type") == "loop":
            continue
        partitions = disk.get("children") or []
        # Bare disk with no partitions — treat as one entry if it has a filesystem
        if not partitions and disk.get("fstype"):
            partitions = [disk]
        for part in partitions:
            if part.get("type") == "loop":
                continue
            fstype = part.get("fstype") or ""
            # Gather all mountpoints (lsblk returns array in mountpoints, or string in mountpoint)
            raw_mps = part.get("mountpoints") or []
            if not raw_mps and part.get("mountpoint"):
                raw_mps = [part.get("mountpoint")]
            mps = [str(m).strip() for m in raw_mps if m and str(m).strip()]

            # Skip partitions that have swap or are mounted to system paths (or subvolumes of /var)
            if fstype == "swap" or any(m in SYSTEM_MOUNTS or m.startswith("/var/") for m in mps):
                continue
            # Skip partitions with no filesystem (unformatted/extended)
            if not fstype:
                continue
            pname = part.get("name", "")
            devices.append({
                "name":       pname,
                "label":      part.get("label") or pname,
                "fstype":     fstype,
                "mountpoint": mps[0] if mps else None,
                "size":       part.get("size", ""),
                "hotplug":    bool(disk.get("hotplug") or part.get("hotplug")),
                "path":       part.get("path") or f"/dev/{pname}",
            })
    return devices


@app.get("/api/storage/list")
async def storage_list():
    """List user-visible mounted and unmounted storage partitions."""
    return {"devices": _lsblk_devices()}


@app.post("/api/storage/mount")
async def storage_mount(req: StorageMountRequest):
    """Mount an unmounted partition via udisksctl (no sudo required)."""
    dev_path = f"/dev/{req.device}" if not req.device.startswith("/dev/") else req.device
    try:
        result = subprocess.run(
            ["udisksctl", "mount", "-b", dev_path, "--no-user-interaction"],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode != 0:
            raise HTTPException(status_code=500, detail=result.stderr.strip() or "Mount failed")
        # Re-query so we return the new mountpoint
        devices = _lsblk_devices()
        name = req.device.lstrip("/dev/").split("/")[-1]
        mounted = next((d for d in devices if d["name"] == name), None)
        return {"ok": True, "mountpoint": mounted["mountpoint"] if mounted else None}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/storage/unmount")
async def storage_unmount(req: StorageMountRequest):
    """Unmount a partition via udisksctl."""
    dev_path = f"/dev/{req.device}" if not req.device.startswith("/dev/") else req.device
    try:
        result = subprocess.run(
            ["udisksctl", "unmount", "-b", dev_path, "--no-user-interaction"],
            capture_output=True, text=True, timeout=15
        )
        if result.returncode != 0:
            raise HTTPException(status_code=500, detail=result.stderr.strip() or "Unmount failed")
        return {"ok": True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


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


def _drain_steers(task_id: str) -> list[str]:
    """Return and clear any steering instructions queued for a running task."""
    task_entry = _chat_tasks.get(task_id)
    if not task_entry:
        return []
    pending = task_entry.get("pending_instructions") or []
    task_entry["pending_instructions"] = []
    return pending


def _read_approval(task_id: str) -> Optional[str]:
    """Return and clear a pending spec-approval decision ('approve'|'revise'|'cancel')."""
    task_entry = _chat_tasks.get(task_id)
    if not task_entry:
        return None
    value = task_entry.get("approval")
    task_entry["approval"] = None
    return value
