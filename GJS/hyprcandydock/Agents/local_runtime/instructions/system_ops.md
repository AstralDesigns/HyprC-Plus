# System Operations & Runtime Guidelines

This guide details operational guidelines for system-level interactions across any project or codebase running within this environment.

## 1. Environment & Shell Context
- Commands execute via `/bin/bash` in non-interactive subshells.
- The desktop environment runs under the modern Hyprland Wayland compositor.
- Standard clipboard utilities: `wl-copy` and `wl-paste` (`xclip`/`xsel` available for XWayland fallbacks).
- Visual surface capture: `grim` (or the built-in `capture_preview` tool) to capture and visually verify any rendered GUI, webview, or desktop surface.
- Note on directory structure: Directory names such as `GJS/` are historical folder paths; all desktop components and services are modern Quickshell, Python, and web runtime architectures.

## 2. Command Execution Safety & Reliability
- Avoid destructive commands (`rm -rf /`, raw disk writes, unconfirmed mass deletion).
- Always verify path existence before executing operations, and use `mkdir -p` when ensuring directories exist.
- Check return codes, standard output, and standard error streams. Do not assume a command succeeded without verifying its exit status.
- When running background servers or long-running tasks, verify socket listening status using standard diagnostic tools (`ss -tulpn`, `lsof -i`, or `curl`).

## 3. Privilege Escalation & Security
- Operations in user project spaces (`$HOME`, workspace roots, `/tmp`) run unprivileged and should never require elevated permissions.
- When a task genuinely requires superuser access (e.g. updating system configurations, package management, daemon configuration):
  - Use non-interactive flags (`sudo -S -k`).
  - In the agent application, privilege escalation requests automatically surface a dedicated authentication card with secure credential resolution.
  - Never store credentials, passwords, or secrets in plaintext files or memories.

## 4. Multi-Stack Project Versatility
- The environment supports diverse software stacks: Node/TypeScript/React, Python, Go, Rust, C/C++, Shell, and QML.
- Apply standard platform tooling idioms appropriate to the stack:
  - Node/Web: `npm run build`, `vite build`, `tsc --noEmit`.
  - Python: `python3 -m py_compile`, `pytest`, `ruff`, `mypy`.
  - Rust: `cargo check`, `cargo test`.
  - Go: `go vet`, `go test ./...`.
  - Shell: `bash -n <script>`.
