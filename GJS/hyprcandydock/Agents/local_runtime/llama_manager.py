"""
llama_manager.py — llama-server lifecycle + GGUF model catalog

Responsibilities:
  - Locate the llama-server binary
  - Start / stop the server subprocess against a selected GGUF
  - Health-check the running server
  - Scan the models directory and return catalog metadata
  - Download a GGUF from a URL (HuggingFace direct link) with async progress
  - Import a GGUF from disk into the models directory
"""

from __future__ import annotations

import asyncio
import os
import re
import shutil
import signal
import subprocess
import time
from pathlib import Path
from typing import AsyncIterator, Optional

import httpx

# ── Constants ─────────────────────────────────────────────────────────────────
LLAMA_PORT = 17843
LLAMA_MODELS_DIR = Path(os.environ.get(
    "HYPRCANDY_LLAMA_MODELS_DIR",
    Path.home() / ".local" / "share" / "hyprcandy" / "llama-models"
))
MODELS_DIR = Path(os.environ.get(
    "HYPRCANDY_MODELS_DIR",
    LLAMA_MODELS_DIR
))
FALLBACK_DIRS = [
    LLAMA_MODELS_DIR,
    Path.home() / ".local" / "share" / "hyprcand" / "llama-models",
    Path.home() / ".local" / "share" / "hyprcandy" / "models",
    Path.home() / ".local" / "share" / "hyprcand" / "models",
]
LLAMA_BINARY_CANDIDATES = [
    "llama-server",
    str(Path.home() / ".local" / "bin" / "llama-server"),
    "/usr/local/bin/llama-server",
    "/usr/bin/llama-server",
    str(Path(__file__).resolve().parent.parent.parent / "native" / "llama.cpp" / "build" / "bin" / "llama-server"),
    str(Path(__file__).resolve().parent.parent.parent / "native" / "llama-server"),
]
GPU_LAYERS = os.environ.get("HYPRCANDY_LLAMA_GPU_LAYERS", "-1")

# ── State ─────────────────────────────────────────────────────────────────────
_server_proc: Optional[subprocess.Popen] = None
_loaded_model: Optional[str] = None          # GGUF path currently served
_server_start_time: float = 0.0


# ── Binary discovery ──────────────────────────────────────────────────────────
def find_llama_server() -> Optional[str]:
    """Return the path to a working llama-server binary, or None."""
    for candidate in LLAMA_BINARY_CANDIDATES:
        resolved = shutil.which(candidate) or (candidate if os.path.isfile(candidate) else None)
        if resolved and os.access(resolved, os.X_OK):
            return resolved
    return None


# ── Model catalog ─────────────────────────────────────────────────────────────
def _parse_quant(filename: str) -> str:
    """Extract quantisation label from filename, e.g. Q4_K_M."""
    match = re.search(r'(Q\d+(?:_K(?:_[MS])?|_\d+)?|IQ\d+_\w+|F16|F32)', filename, re.IGNORECASE)
    return match.group(1).upper() if match else "GGUF"


def list_models() -> list[dict]:
    """Return installed GGUF models with metadata from all model directories."""
    LLAMA_MODELS_DIR.mkdir(parents=True, exist_ok=True)
    status = server_status()
    active_path = status.get("model")
    active_stem = status.get("model_name")

    models = []
    seen = set()
    for directory in FALLBACK_DIRS:
        if not directory.exists():
            continue
        for path in sorted(directory.glob("*.gguf")):
            if path.name in seen:
                continue
            seen.add(path.name)
            stat = path.stat()
            is_loaded = bool(
                status.get("running") and (
                    (active_path and (str(path) == active_path or path.name == Path(active_path).name))
                    or (active_stem and path.stem == active_stem)
                )
            )
            models.append({
                "id": path.stem,
                "filename": path.name,
                "path": str(path),
                "size_bytes": stat.st_size,
                "size_label": _human_size(stat.st_size),
                "quant": _parse_quant(path.name),
                "loaded": is_loaded,
            })
    return models


def _human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def _resolve_source_path(src_str: str) -> Optional[Path]:
    p = Path(src_str).expanduser()
    if p.is_file():
        return p
    fname = p.name
    search_dirs = [
        LLAMA_MODELS_DIR,
        Path.home() / ".local" / "share" / "hyprcand" / "llama-models",
        Path.home() / ".local" / "share" / "hyprcandy" / "models",
        Path.home() / ".local" / "share" / "hyprcand" / "models",
        Path.home() / "Downloads",
        Path.home(),
        Path.home() / ".cache",
    ]
    for d in search_dirs:
        candidate = d / fname
        if candidate.is_file():
            return candidate
    return None


def import_model(src_path: str) -> dict:
    """Copy or symlink a GGUF file into the models directory."""
    src = _resolve_source_path(src_path)
    if not src:
        raise FileNotFoundError(f"Source file not found: {src_path}")
    LLAMA_MODELS_DIR.mkdir(parents=True, exist_ok=True)
    dest = LLAMA_MODELS_DIR / src.name
    if src.resolve() != dest.resolve():
        if not dest.exists():
            shutil.copy2(src, dest)
    stat = dest.stat()
    return {
        "filename": dest.name,
        "path": str(dest),
        "size_bytes": stat.st_size,
        "size_label": _human_size(stat.st_size),
        "quant": _parse_quant(dest.name),
    }


# ── Download by URL ───────────────────────────────────────────────────────────
async def download_model(url: str, filename: Optional[str] = None) -> AsyncIterator[dict]:
    """
    Stream-download a GGUF from a URL (HuggingFace direct link).
    Yields progress dicts: {loaded, total, text, done, path?}
    """
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    if not filename:
        filename = url.split("/")[-1].split("?")[0]
    if not filename.endswith(".gguf"):
        filename += ".gguf"
    dest = MODELS_DIR / filename

    async with httpx.AsyncClient(follow_redirects=True, timeout=None) as client:
        async with client.stream("GET", url) as resp:
            resp.raise_for_status()
            total = int(resp.headers.get("content-length", 0))
            loaded = 0
            with open(dest, "wb") as f:
                async for chunk in resp.aiter_bytes(65536):
                    f.write(chunk)
                    loaded += len(chunk)
                    pct = int(loaded * 100 / total) if total else 0
                    yield {
                        "loaded": loaded,
                        "total": total,
                        "percent": pct,
                        "text": f"Downloading {filename}: {_human_size(loaded)} / {_human_size(total) if total else '?'}",
                        "done": False,
                    }
    yield {
        "loaded": loaded,
        "total": total,
        "percent": 100,
        "text": f"Downloaded {filename}",
        "done": True,
        "path": str(dest),
        "filename": filename,
    }


# ── Server lifecycle ──────────────────────────────────────────────────────────
def server_status() -> dict:
    global _server_proc, _loaded_model, _server_start_time
    if _server_proc is not None:
        if _server_proc.poll() is None:
            uptime = int(time.time() - _server_start_time)
            return {
                "running": True,
                "port": LLAMA_PORT,
                "model": _loaded_model,
                "model_name": Path(_loaded_model).stem if _loaded_model else None,
                "uptime": uptime,
            }
        else:
            _server_proc = None

    # Check if a llama-server is running on LLAMA_PORT (e.g. started by GJS or previous session)
    try:
        with httpx.Client(timeout=1.0) as client:
            r = client.get(f"http://127.0.0.1:{LLAMA_PORT}/health")
            if r.status_code == 200:
                detected_path = _loaded_model
                try:
                    pr = client.get(f"http://127.0.0.1:{LLAMA_PORT}/props")
                    if pr.status_code == 200:
                        props = pr.json()
                        p = props.get("model_path")
                        if p:
                            detected_path = p
                            _loaded_model = p
                except Exception:
                    pass
                if not detected_path:
                    try:
                        import json
                        state_path = Path.home() / ".local" / "share" / "hyprcandy" / "llama-server-state.json"
                        if state_path.exists():
                            data = json.loads(state_path.read_text())
                            if data.get("path"):
                                detected_path = data["path"]
                            elif data.get("file"):
                                detected_path = str(LLAMA_MODELS_DIR / data["file"])
                            _loaded_model = detected_path
                    except Exception:
                        pass
                return {
                    "running": True,
                    "port": LLAMA_PORT,
                    "model": detected_path,
                    "model_name": Path(detected_path).stem if detected_path else "llama-server",
                    "uptime": int(time.time() - _server_start_time) if _server_start_time else 0,
                }
    except Exception:
        pass

    _loaded_model = None
    return {"running": False, "port": LLAMA_PORT, "model": None, "uptime": 0}


async def start_server(model_path: str, ctx_size: int = 0, max_tokens: int = 2048) -> dict:
    """Launch llama-server against a GGUF. Stops the previous server if running."""
    global _server_proc, _loaded_model, _server_start_time

    binary = find_llama_server()
    if not binary:
        raise RuntimeError(
            "llama-server binary not found. Install it via build-llama-server.sh or place it in ~/.local/bin/"
        )

    # Stop existing server
    await stop_server()

    path = Path(model_path)
    if not path.exists():
        # Try resolving relative to LLAMA_MODELS_DIR or via _resolve_source_path
        resolved = _resolve_source_path(model_path)
        if resolved and resolved.exists():
            path = resolved
        else:
            raise FileNotFoundError(f"GGUF not found: {model_path}")

    ctx = ctx_size if ctx_size > 0 else 16384
    cmd = [
        binary,
        "--model", str(path),
        "--port", str(LLAMA_PORT),
        "--host", "127.0.0.1",
        "--ctx-size", str(ctx),
        "--n-predict", str(max_tokens),
        "--parallel", "1",
        # -1 means offload every layer supported by the selected backend.
        # The previous default left llama-server on CPU (or backend default),
        # making the launcher’s discrete-GPU selection ineffective.
        "--n-gpu-layers", GPU_LAYERS,
        "--jinja",
        "--log-disable",
    ]

    # Keep the device choice explicit when the runtime is launched outside
    # the GTK launcher. The launcher exports these variables after selecting
    # the accessible discrete render node; Vulkan/GL loaders inherit them.
    selected_prime = os.environ.get("HYPRCANDY_LLAMA_DRI_PRIME")
    if selected_prime:
        os.environ["DRI_PRIME"] = selected_prime
    selected_pci = os.environ.get("HYPRCANDY_LLAMA_GPU_PCI", "auto")
    print(f"[llama-runtime] starting {path.name} with n-gpu-layers={GPU_LAYERS}, gpu={selected_pci}, DRI_PRIME={os.environ.get('DRI_PRIME', '')}", flush=True)

    _server_proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid,
    )
    _loaded_model = str(path)
    _server_start_time = time.time()

    # Wait up to 30s for health
    for _ in range(60):
        await asyncio.sleep(0.5)
        if _server_proc.poll() is not None:
            _loaded_model = None
            raise RuntimeError("llama-server exited unexpectedly during startup")
        try:
            async with httpx.AsyncClient(timeout=2.0) as client:
                r = await client.get(f"http://127.0.0.1:{LLAMA_PORT}/health")
                if r.status_code == 200:
                    # Sync state files so GJS and launcher stay in sync
                    try:
                        import json
                        state_path = Path.home() / ".local" / "share" / "hyprcandy" / "llama-server-state.json"
                        state_path.parent.mkdir(parents=True, exist_ok=True)
                        state_path.write_text(json.dumps({
                            "id": path.stem,
                            "file": path.name,
                            "path": str(path),
                            "updatedAt": int(time.time() * 1000)
                        }))
                        active_path = LLAMA_MODELS_DIR / "active-model.json"
                        active_path.parent.mkdir(parents=True, exist_ok=True)
                        active_path.write_text(json.dumps({
                            "id": path.stem,
                            "file": path.name,
                            "path": str(path)
                        }))
                    except Exception:
                        pass
                    return server_status()
        except Exception:
            pass

    raise TimeoutError("llama-server did not become healthy within 30 seconds")


async def stop_server() -> dict:
    global _server_proc, _loaded_model
    if _server_proc and _server_proc.poll() is None:
        try:
            os.killpg(os.getpgid(_server_proc.pid), signal.SIGTERM)
            try:
                _server_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(os.getpgid(_server_proc.pid), signal.SIGKILL)
        except Exception:
            pass
    _server_proc = None
    _loaded_model = None

    # Also kill any external llama-server process bound to LLAMA_PORT
    try:
        subprocess.run(["pkill", "-f", "llama-server.*17843"], check=False)
        subprocess.run(["pkill", "-f", "llama-server.*llama-models"], check=False)
    except Exception:
        pass

    return {"running": False, "port": LLAMA_PORT, "model": None}


async def health_check() -> bool:
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            r = await client.get(f"http://127.0.0.1:{LLAMA_PORT}/health")
            return r.status_code == 200
    except Exception:
        return False


async def delete_model(path_or_filename: str) -> dict:
    """Delete a single GGUF model from disk. Stops server if it's currently loaded."""
    global _loaded_model
    target = _resolve_source_path(path_or_filename)
    if not target or not target.exists():
        raise FileNotFoundError(f"Model not found: {path_or_filename}")

    status = server_status()
    if status.get("running"):
        active_p = status.get("model")
        if active_p and (str(target) == active_p or target.name == Path(active_p).name):
            await stop_server()

    target.unlink()
    return {"deleted": True, "filename": target.name, "path": str(target)}


async def clear_all_models() -> dict:
    """Stop server and delete all GGUF models from model directories."""
    await stop_server()
    deleted = []
    for directory in FALLBACK_DIRS:
        if not directory.exists():
            continue
        for gguf in directory.glob("*.gguf"):
            try:
                gguf.unlink()
                deleted.append(gguf.name)
            except Exception:
                pass
    return {"cleared": True, "deleted_count": len(deleted), "deleted": deleted}
