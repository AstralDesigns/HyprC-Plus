"""
byok_client.py — Bring Your Own Key (BYOK) cloud provider client

Supports: OpenRouter, Groq, Google Gemini, Anthropic, OpenAI, xAI (Grok)
All providers yield the same event dict format as local_backend in agent_loop.py:
  {"type": "token",      "content": str}
  {"type": "tool_calls", "calls": [{"id": str, "name": str, "arguments": str}]}
  {"type": "done"}
  {"type": "error",      "message": str}
"""

from __future__ import annotations

import json
from typing import AsyncIterator

import httpx

# ── Provider configs ──────────────────────────────────────────────────────────
# Order: OpenRouter, Groq, Google, Anthropic, OpenAI, Grok
PROVIDERS = {
    "openrouter": {
        "name": "OpenRouter",
        "key_hint": "sk-or-v1-...",
        "api_key_url": "https://openrouter.ai/keys",
        "models": [
            {"id": "openrouter/free",                       "name": "OpenRouter Free (Auto)",  "desc": "Auto-cycles best available free models. NVIDIA Nemotron, Gemma 4, and other free-tier models.", "context": "128k tokens"},
            {"id": "anthropic/claude-fable-5-1",            "name": "Claude Fable 5.1",         "desc": "Anthropic flagship (Sep 2026). Best-in-class reasoning & long-horizon agentic work.",           "context": "1M tokens"},
            {"id": "anthropic/claude-sonnet-5",             "name": "Claude Sonnet 5",          "desc": "Best balance of speed & intelligence for production agentic coding.",                           "context": "1M tokens"},
            {"id": "openai/gpt-6-astra",                    "name": "GPT-6 Astra",              "desc": "OpenAI flagship (Sep 2026). Frontier reasoning, computer use & advanced agents.",                "context": "128k tokens"},
            {"id": "openai/gpt-5.6-sol",                    "name": "GPT-5.6 Sol",              "desc": "High-capability flagship for complex professional work & reasoning.",                            "context": "128k tokens"},
            {"id": "google/gemini-3.8-flash",               "name": "Gemini 3.8 Flash",         "desc": "Google best Flash model — long-horizon coding & agents, 65K output.",                          "context": "1M tokens"},
            {"id": "x-ai/grok-4.6",                         "name": "Grok 4.6",                 "desc": "xAI flagship (Aug 2026). Real-time knowledge, 500K context, advanced reasoning.",               "context": "500k tokens"},
            {"id": "deepseek/deepseek-r1",                  "name": "DeepSeek R1",              "desc": "Top open reasoning model for complex code & math.",                                             "context": "128k tokens"},
            {"id": "meta-llama/llama-3.3-70b-instruct",     "name": "Llama 3.3 70B",            "desc": "Meta open-weights flagship. High-speed versatile model.",                                      "context": "128k tokens"},
        ],
    },
    "groq": {
        "name": "Groq",
        "key_hint": "gsk_...",
        "api_key_url": "https://console.groq.com/keys",
        "models": [
            {"id": "openai/gpt-oss-120b",              "name": "GPT-OSS 120B",            "desc": "OpenAI open-weights flagship on Groq LPU. Complex reasoning & agentic tasks. Recommended.",     "context": "128k tokens"},
            {"id": "openai/gpt-oss-20b",               "name": "GPT-OSS 20B",             "desc": "Compact open-weights model. Fast inference, cost-efficient agentic workflows.",                   "context": "128k tokens"},
            {"id": "llama-3.3-70b-versatile",          "name": "Llama 3.3 70B",           "desc": "Ultra-fast LPU inference (~300 t/s). Meta open-weights flagship.",                               "context": "128k tokens"},
            {"id": "llama-3.1-8b-instant",             "name": "Llama 3.1 8B Instant",    "desc": "Blazing speed (~800 t/s). Best for low-latency quick answers.",                                   "context": "128k tokens"},
            {"id": "qwen/qwen3-32b",                   "name": "Qwen3 32B",               "desc": "Alibaba open-weights high-speed coding & reasoning model on Groq.",                              "context": "128k tokens"},
            {"id": "groq/compound",                    "name": "Groq Compound",           "desc": "Groq compound model with integrated tool use & web search.",                                     "context": "128k tokens"},
            {"id": "groq/compound-mini",               "name": "Groq Compound Mini",      "desc": "Fast, cost-efficient Groq compound model for everyday tasks.",                                   "context": "128k tokens"},
        ],
    },
    "google": {
        "name": "Google Gemini",
        "key_hint": "AIza...",
        "api_key_url": "https://aistudio.google.com/apikey",
        "models": [
            {"id": "gemini-3.8-flash",                  "name": "Gemini 3.8 Flash",        "desc": "Best Flash — long-horizon coding & agents, 65K output. Recommended.",                  "context": "1M tokens"},
            {"id": "gemini-3.6-flash",                  "name": "Gemini 3.6 Flash",        "desc": "Previous Flash generation — fast & capable.",                                          "context": "1M tokens"},
            {"id": "gemini-3.1-pro-preview",            "name": "Gemini 3.1 Pro",          "desc": "Most intelligent Gemini model. Paid tier only.",                                       "context": "1M tokens"},
            {"id": "gemini-3.1-flash-lite",             "name": "Gemini 3.1 Flash-Lite",   "desc": "Ultra-fast lightweight model. Free tier friendly.",                                   "context": "1M tokens"},
        ],
    },
    "anthropic": {
        "name": "Anthropic",
        "key_hint": "sk-ant-...",
        "api_key_url": "https://console.anthropic.com/settings/keys",
        "models": [
            {"id": "claude-fable-5-1",                  "name": "Claude Fable 5.1",        "desc": "Anthropic flagship (Sep 2026). Best demanding reasoning & long-horizon agentic work.",         "context": "1M tokens"},
            {"id": "claude-opus-5",                     "name": "Claude Opus 5",           "desc": "Frontier agentic coding & enterprise-grade complex reasoning.",                              "context": "1M tokens"},
            {"id": "claude-sonnet-5",                   "name": "Claude Sonnet 5",         "desc": "Recommended default. Best balance of speed & intelligence for production. Recommended.",     "context": "1M tokens"},
            {"id": "claude-haiku-4-5-20251001",              "name": "Claude Haiku 4.5",        "desc": "Ultra-fast & cost-effective. Best for high-volume latency-sensitive tasks.",                 "context": "200k tokens"},
        ],
    },
    "openai": {
        "name": "OpenAI",
        "key_hint": "sk-...",
        "api_key_url": "https://platform.openai.com/api-keys",
        "models": [
            {"id": "gpt-6-astra",                       "name": "GPT-6 Astra",             "desc": "OpenAI flagship (Sep 2026). Frontier reasoning, computer use & advanced agentic tasks.",      "context": "128k tokens"},
            {"id": "gpt-5.6-sol",                       "name": "GPT-5.6 Sol",             "desc": "High-capability flagship for complex professional work. Also accessible as gpt-5.6.",        "context": "128k tokens"},
            {"id": "gpt-5.6-terra",                     "name": "GPT-5.6 Terra",           "desc": "Balanced model for general production use. Performance vs. cost sweet spot.",                "context": "128k tokens"},
            {"id": "gpt-5.6-luna",                      "name": "GPT-5.6 Luna",            "desc": "Cost-efficient model for high-volume workloads. Recommended for cost-sensitive tasks.",     "context": "128k tokens"},
            {"id": "o4-mini",                           "name": "o4-mini",                 "desc": "Optimized reasoning model for fast math, coding & STEM.",                                    "context": "200k tokens"},
            {"id": "o3",                                "name": "o3",                      "desc": "Advanced reasoning for complex analytical & scientific tasks.",                              "context": "200k tokens"},
        ],
    },
    "xai": {
        "name": "xAI (Grok)",
        "key_hint": "xai-...",
        "api_key_url": "https://console.x.ai/",
        "models": [
            {"id": "grok-4.6",                          "name": "Grok 4.6",                "desc": "xAI flagship (Aug 2026). Real-time knowledge, 500K context, advanced reasoning & tool use.",   "context": "500k tokens"},
            {"id": "grok-4.6-latest",                   "name": "Grok 4.6 Latest",         "desc": "Auto-updated alias to the very latest Grok 4.6 build. Best for cutting-edge tasks.",           "context": "500k tokens"},
            {"id": "grok-3",                            "name": "Grok 3",                  "desc": "Previous generation flagship. Stable, reliable general-purpose intelligence.",                 "context": "131k tokens"},
        ],
    },
}


def get_provider_models(provider: str) -> list[dict]:
    return PROVIDERS.get(provider, {}).get("models", [])


async def fetch_remote_models(provider: str, api_key: str | None = None) -> list[dict]:
    """Dynamically fetch provider's agentic models list via their respective endpoint.
    Filters and prioritizes models supporting function calling/instruct/chat.
    Gracefully falls back to curated static models if network fails or key is missing.
    """
    fallback = get_provider_models(provider)
    clean_key = (api_key or "").strip()

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            if provider == "openrouter":
                headers = {}
                if clean_key:
                    headers["Authorization"] = f"Bearer {clean_key}"
                resp = await client.get("https://openrouter.ai/api/v1/models", headers=headers)
                if resp.status_code == 200:
                    data = resp.json().get("data", [])
                    models = []
                    for m in data:
                        mid = m.get("id", "")
                        mname = m.get("name") or mid
                        mdesc = m.get("description") or "OpenRouter model"
                        if len(mdesc) > 130:
                            mdesc = mdesc[:127] + "..."
                        ctx_len = m.get("context_length") or 128000
                        ctx_str = f"{ctx_len // 1000}k tokens" if ctx_len >= 1000 else f"{ctx_len} tokens"
                        params = m.get("supported_parameters") or []
                        has_tools = "tools" in params or "tool_choice" in params
                        models.append({
                            "id": mid,
                            "name": mname,
                            "desc": mdesc,
                            "context": ctx_str,
                            "has_tools": has_tools,
                        })
                    priority_prefixes = ("anthropic/", "openai/", "google/", "meta-llama/", "deepseek/", "x-ai/", "qwen/", "mistralai/")
                    def model_sort_key(item):
                        is_prio = any(item["id"].startswith(p) for p in priority_prefixes)
                        return (0 if (item["has_tools"] and is_prio) else 1 if item["has_tools"] else 2 if is_prio else 3, item["name"].lower())
                    models.sort(key=model_sort_key)
                    if models:
                        return models

            elif provider == "groq":
                if not clean_key:
                    return fallback
                resp = await client.get(
                    "https://api.groq.com/openai/v1/models",
                    headers={"Authorization": f"Bearer {clean_key}"}
                )
                if resp.status_code == 200:
                    data = resp.json().get("data", [])
                    models = []
                    for m in data:
                        mid = m.get("id", "")
                        if any(x in mid.lower() for x in ("whisper", "guard", "safeguard")):
                            continue
                        if not m.get("active", True):
                            continue
                        ctx_len = m.get("context_window") or 131072
                        ctx_str = f"{ctx_len // 1000}k tokens"
                        name = mid.replace("-", " ").title()
                        desc = "Groq LPU ultra-fast inference (~300-800 t/s). Active model."
                        models.append({
                            "id": mid,
                            "name": name,
                            "desc": desc,
                            "context": ctx_str,
                        })
                    if models:
                        models.sort(key=lambda x: (0 if "llama-3.3" in x["id"] or "gpt-oss" in x["id"] or "qwen" in x["id"] else 1, x["name"]))
                        return models

            elif provider == "google":
                if not clean_key:
                    return fallback
                resp = await client.get(
                    f"https://generativelanguage.googleapis.com/v1beta/models?key={clean_key}"
                )
                if resp.status_code == 200:
                    data = resp.json().get("models", [])
                    models = []
                    for m in data:
                        methods = m.get("supportedGenerationMethods", [])
                        if "generateContent" not in methods:
                            continue
                        raw_id = m.get("name", "")
                        mid = raw_id.removeprefix("models/")
                        if "embedding" in mid.lower() or "aqa" in mid.lower():
                            continue
                        display_name = m.get("displayName") or mid
                        desc = m.get("description") or "Google Gemini generative model."
                        if len(desc) > 130:
                            desc = desc[:127] + "..."
                        ctx_len = m.get("inputTokenLimit") or 1048576
                        ctx_str = f"{ctx_len // 1000}k tokens" if ctx_len >= 1000 else f"{ctx_len} tokens"
                        models.append({
                            "id": mid,
                            "name": display_name,
                            "desc": desc,
                            "context": ctx_str,
                        })
                    if models:
                        models.sort(key=lambda x: (0 if "flash" in x["id"] or "pro" in x["id"] else 1, x["name"]))
                        return models

            elif provider == "anthropic":
                if not clean_key:
                    return fallback
                resp = await client.get(
                    "https://api.anthropic.com/v1/models",
                    headers={
                        "x-api-key": clean_key,
                        "anthropic-version": "2023-06-01",
                    }
                )
                if resp.status_code == 200:
                    data = resp.json().get("data", [])
                    models = []
                    for m in data:
                        mid = m.get("id", "")
                        name = m.get("display_name") or mid
                        desc = "Anthropic Claude frontier reasoning & agentic model."
                        ctx_str = "200k+ tokens"
                        models.append({
                            "id": mid,
                            "name": name,
                            "desc": desc,
                            "context": ctx_str,
                        })
                    if models:
                        models.sort(key=lambda x: (0 if "sonnet" in x["id"] else 1 if "opus" in x["id"] else 2, x["name"]))
                        return models

            elif provider == "openai":
                if not clean_key:
                    return fallback
                resp = await client.get(
                    "https://api.openai.com/v1/models",
                    headers={"Authorization": f"Bearer {clean_key}"}
                )
                if resp.status_code == 200:
                    data = resp.json().get("data", [])
                    models = []
                    excluded_keywords = ("whisper", "tts", "dall-e", "embedding", "babbage", "davinci", "curie", "ada", "realtime", "audio", "moderation")
                    for m in data:
                        mid = m.get("id", "")
                        mid_lower = mid.lower()
                        if any(kw in mid_lower for kw in excluded_keywords):
                            continue
                        if not (mid_lower.startswith("gpt-") or mid_lower.startswith("o1") or mid_lower.startswith("o3") or mid_lower.startswith("o4") or "chat" in mid_lower):
                            continue
                        models.append({
                            "id": mid,
                            "name": mid,
                            "desc": "OpenAI frontier reasoning & tool-calling model.",
                            "context": "128k-200k tokens",
                        })
                    if models:
                        models.sort(key=lambda x: (0 if x["id"].startswith("gpt-4o") or x["id"].startswith("o3") or x["id"].startswith("gpt-5") else 1, x["name"]))
                        return models

            elif provider == "xai":
                if not clean_key:
                    return fallback
                resp = await client.get(
                    "https://api.x.ai/v1/models",
                    headers={"Authorization": f"Bearer {clean_key}"}
                )
                if resp.status_code == 200:
                    data = resp.json().get("data", [])
                    models = []
                    for m in data:
                        mid = m.get("id", "")
                        if not mid.lower().startswith("grok"):
                            continue
                        name = mid.replace("-", " ").title()
                        desc = "xAI Grok advanced reasoning & real-time knowledge."
                        ctx_str = "131k-500k tokens"
                        models.append({
                            "id": mid,
                            "name": name,
                            "desc": desc,
                            "context": ctx_str,
                        })
                    if models:
                        models.sort(key=lambda x: (0 if "latest" in x["id"] else 1, x["name"]))
                        return models
    except Exception as exc:
        print(f"[byok_client] Error fetching remote models for {provider}: {exc}")

    return fallback


# ── Google Gemini streaming (native API, Tinker-style function calling) ────────
async def _stream_google(
    messages: list[dict],
    model: str,
    api_key: str,
    tools_schema: list[dict],
) -> AsyncIterator[dict]:
    """Stream from Google Generative Language API using native function calling."""
    base_url = "https://generativelanguage.googleapis.com/v1beta"

    # Convert OpenAI-style messages → Gemini contents format
    system_text = ""
    contents = []
    for m in messages:
        role = m.get("role", "user")
        content = m.get("content") or ""
        if role == "system":
            system_text = content
            continue
        elif role == "user":
            g_role = "user"
        elif role == "assistant":
            g_role = "model"
        elif role == "tool":
            # Tool response — wrap as user turn with function response
            tool_call_id = m.get("tool_call_id", "")
            contents.append({
                "role": "user",
                "parts": [{"functionResponse": {
                    "name": tool_call_id,
                    "response": {"result": content},
                }}],
            })
            continue
        else:
            continue

        # Handle assistant messages with tool_calls
        if role == "assistant" and m.get("tool_calls"):
            parts = []
            if content:
                parts.append({"text": content})
            for tc in m["tool_calls"]:
                fn = tc.get("function", {})
                args = fn.get("arguments", "{}")
                try:
                    args_dict = json.loads(args) if isinstance(args, str) else args
                except Exception:
                    args_dict = {}
                parts.append({"functionCall": {
                    "name": fn.get("name", ""),
                    "args": args_dict,
                }})
            contents.append({"role": "model", "parts": parts})
            continue

        if content:
            contents.append({"role": g_role, "parts": [{"text": content}]})

    # Build function declarations from tools schema (Tinker-style)
    function_declarations = []
    for tool in tools_schema:
        fn = tool.get("function", {})
        if fn.get("name"):
            decl = {
                "name": fn["name"],
                "description": fn.get("description", ""),
            }
            params = fn.get("parameters")
            if params:
                decl["parameters"] = params
            function_declarations.append(decl)

    # Gemini 3 models support up to 65K output tokens and benefit from
    # a thinking budget for complex agentic tasks (matches tinker-install.sh).
    is_gemini3 = model.startswith("gemini-3")
    max_tokens = 65536 if is_gemini3 else 8192

    payload: dict = {
        "contents": contents,
        "generationConfig": {
            "temperature": 0.2,
            "maxOutputTokens": max_tokens,
            **({"thinkingConfig": {"thinkingBudget": 8192}} if is_gemini3 else {}),
        },
    }

    if system_text:
        payload["systemInstruction"] = {"parts": [{"text": system_text}]}

    if function_declarations:
        payload["tools"] = [{"functionDeclarations": function_declarations}]
        payload["toolConfig"] = {
            "functionCallingConfig": {"mode": "AUTO"},
        }

    clean_model = model.removeprefix("models/")
    url = f"{base_url}/models/{clean_model}:streamGenerateContent?alt=sse&key={api_key}"

    tool_call_buffer: dict[str, dict] = {}

    try:
        async with httpx.AsyncClient(timeout=180.0) as client:
            async with client.stream("POST", url, json=payload,
                                     headers={"Content-Type": "application/json"}) as resp:
                if resp.status_code == 400:
                    body = await resp.aread()
                    yield {"type": "error", "message": f"Google API 400: {body[:300].decode()}"}
                    return
                if resp.status_code == 401 or resp.status_code == 403:
                    yield {"type": "error", "message": "Google API: Invalid or unauthorized API key. Check your Gemini key."}
                    return
                if resp.status_code == 429:
                    yield {"type": "error", "message": "Google API: Rate limit exceeded. Please wait and retry."}
                    return
                if not resp.is_success:
                    body = await resp.aread()
                    yield {"type": "error", "message": f"Google API {resp.status_code}: {body[:200].decode()}"}
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

                        for candidate in chunk.get("candidates", []):
                            content_block = candidate.get("content", {})
                            for part in content_block.get("parts", []):
                                if "text" in part:
                                    yield {"type": "token", "content": part["text"]}
                                elif "functionCall" in part:
                                    fc = part["functionCall"]
                                    call_id = f"google_{fc.get('name', 'fn')}_{len(tool_call_buffer)}"
                                    tool_call_buffer[call_id] = {
                                        "id": call_id,
                                        "name": fc.get("name", ""),
                                        "arguments": json.dumps(fc.get("args", {})),
                                    }

    except httpx.ConnectError:
        yield {"type": "error", "message": "Cannot reach Google API. Check internet connection."}
        return
    except Exception as exc:
        yield {"type": "error", "message": f"Google stream error: {exc}"}
        return

    if tool_call_buffer:
        yield {"type": "tool_calls", "calls": list(tool_call_buffer.values())}

    yield {"type": "done"}


# ── OpenAI-compatible streaming (OpenAI, xAI) ─────────────────────────────────
async def _stream_openai_compat(
    messages: list[dict],
    model: str,
    api_key: str,
    base_url: str,
    tools_schema: list[dict],
    extra_headers: dict | None = None,
) -> AsyncIterator[dict]:
    """Stream from OpenAI-compatible API."""
    payload = {
        "model": model,
        "messages": messages,
        "stream": True,
        "temperature": 0.2,
        "max_tokens": 8192,
    }
    if tools_schema:
        payload["tools"] = tools_schema
        payload["tool_choice"] = "auto"

    tool_call_buffer: dict[str, dict] = {}

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    if extra_headers:
        headers.update(extra_headers)

    try:
        async with httpx.AsyncClient(timeout=180.0) as client:
            async with client.stream(
                "POST",
                f"{base_url}/chat/completions",
                json=payload,
                headers=headers,
            ) as resp:
                if resp.status_code == 401:
                    yield {"type": "error", "message": "Invalid API key."}
                    return
                if resp.status_code == 429:
                    yield {"type": "error", "message": "Rate limit exceeded. Please wait and retry."}
                    return
                if not resp.is_success:
                    body = await resp.aread()
                    yield {"type": "error", "message": f"API error {resp.status_code}: {body[:200].decode()}"}
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
                            buf["id"] = buf["id"] or tc_delta.get("id", f"call_{idx}")
                            fn = tc_delta.get("function", {})
                            buf["name"] += fn.get("name", "")
                            buf["arguments"] += fn.get("arguments", "")
                        if choice.get("finish_reason"):
                            break

    except httpx.ConnectError:
        yield {"type": "error", "message": "Cannot reach API endpoint. Check internet."}
        return
    except Exception as exc:
        yield {"type": "error", "message": f"Stream error: {exc}"}
        return

    if tool_call_buffer:
        yield {"type": "tool_calls", "calls": list(tool_call_buffer.values())}
    yield {"type": "done"}


# ── Anthropic streaming ────────────────────────────────────────────────────────
async def _stream_anthropic(
    messages: list[dict],
    model: str,
    api_key: str,
    tools_schema: list[dict],
) -> AsyncIterator[dict]:
    """Stream from Anthropic Messages API."""
    # Extract system message
    system_text = ""
    filtered = []
    for m in messages:
        if m.get("role") == "system":
            system_text = m.get("content", "")
        else:
            filtered.append({"role": m["role"], "content": m.get("content") or ""})

    # Convert tool schemas to Anthropic format
    anthropic_tools = []
    for tool in tools_schema:
        fn = tool.get("function", {})
        if fn.get("name"):
            anthropic_tools.append({
                "name": fn["name"],
                "description": fn.get("description", ""),
                "input_schema": fn.get("parameters", {"type": "object", "properties": {}}),
            })

    payload: dict = {
        "model": model,
        "messages": filtered,
        "max_tokens": 8192,
        "stream": True,
    }
    if system_text:
        payload["system"] = system_text
    if anthropic_tools:
        payload["tools"] = anthropic_tools

    tool_call_buffer: dict[str, dict] = {}

    try:
        async with httpx.AsyncClient(timeout=180.0) as client:
            async with client.stream(
                "POST",
                "https://api.anthropic.com/v1/messages",
                json=payload,
                headers={
                    "x-api-key": api_key,
                    "anthropic-version": "2023-06-01",
                    "content-type": "application/json",
                },
            ) as resp:
                if resp.status_code == 401:
                    yield {"type": "error", "message": "Invalid Anthropic API key."}
                    return
                if resp.status_code == 429:
                    yield {"type": "error", "message": "Anthropic rate limit exceeded."}
                    return
                if not resp.is_success:
                    body = await resp.aread()
                    yield {"type": "error", "message": f"Anthropic API {resp.status_code}: {body[:200].decode()}"}
                    return

                buffer = ""
                current_tool_id = None
                async for raw_chunk in resp.aiter_bytes(1024):
                    buffer += raw_chunk.decode(errors="replace")
                    while "\n" in buffer:
                        line, buffer = buffer.split("\n", 1)
                        line = line.strip()
                        if not line or not line.startswith("data:"):
                            continue
                        data = line[5:].strip()
                        try:
                            event = json.loads(data)
                        except json.JSONDecodeError:
                            continue

                        etype = event.get("type", "")
                        if etype == "content_block_start":
                            block = event.get("content_block", {})
                            if block.get("type") == "tool_use":
                                current_tool_id = block.get("id", f"ant_{len(tool_call_buffer)}")
                                tool_call_buffer[current_tool_id] = {
                                    "id": current_tool_id,
                                    "name": block.get("name", ""),
                                    "arguments": "",
                                }
                        elif etype == "content_block_delta":
                            delta = event.get("delta", {})
                            if delta.get("type") == "text_delta":
                                yield {"type": "token", "content": delta.get("text", "")}
                            elif delta.get("type") == "input_json_delta" and current_tool_id:
                                tool_call_buffer[current_tool_id]["arguments"] += delta.get("partial_json", "")
                        elif etype == "message_stop":
                            break

    except httpx.ConnectError:
        yield {"type": "error", "message": "Cannot reach Anthropic API. Check internet."}
        return
    except Exception as exc:
        yield {"type": "error", "message": f"Anthropic stream error: {exc}"}
        return

    if tool_call_buffer:
        yield {"type": "tool_calls", "calls": list(tool_call_buffer.values())}
    yield {"type": "done"}


# ── Public entry point ────────────────────────────────────────────────────────
async def stream_byok(
    messages: list[dict],
    provider: str,
    model: str,
    api_key: str,
    tools_schema: list[dict] | None = None,
) -> AsyncIterator[dict]:
    """Route to the correct BYOK provider backend."""
    ts = tools_schema or []

    if provider == "openrouter":
        # Default to 'openrouter/free' if no specific model was selected
        target_model = model.strip() if model and model.strip() else "openrouter/free"
        extra = {
            "HTTP-Referer": "https://hyprcandy.app",
            "X-Title": "HyprCandy Workspace",
        }
        async for event in _stream_openai_compat(
            messages, target_model, api_key, "https://openrouter.ai/api/v1", ts, extra_headers=extra
        ):
            yield event

    elif provider == "groq":
        target_model = model.strip() if model and model.strip() else "openai/gpt-oss-120b"
        async for event in _stream_openai_compat(
            messages, target_model, api_key, "https://api.groq.com/openai/v1", ts
        ):
            yield event

    elif provider == "google":
        async for event in _stream_google(messages, model, api_key, ts):
            yield event

    elif provider == "openai":
        async for event in _stream_openai_compat(
            messages, model, api_key, "https://api.openai.com/v1", ts
        ):
            yield event

    elif provider == "xai":
        async for event in _stream_openai_compat(
            messages, model, api_key, "https://api.x.ai/v1", ts
        ):
            yield event

    elif provider == "anthropic":
        async for event in _stream_anthropic(messages, model, api_key, ts):
            yield event

    else:
        yield {"type": "error", "message": f"Unknown BYOK provider: {provider}"}
