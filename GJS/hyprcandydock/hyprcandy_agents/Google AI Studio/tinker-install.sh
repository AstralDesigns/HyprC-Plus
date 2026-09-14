#!/usr/bin/env bash
#
# Tinker v7.5 - Enhanced Agentic Edition
# - Fixed Gemini function calling loop
# - Internal to-do list for task tracking
# - Smart command execution (safe/elevated/password)
# - Better file discipline in prompts
# - Updated to Gemini 3 model family (default: Gemini 3.8 Flash)
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

INSTALL_DIR="$HOME/.tinker"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/tinker"
CACHE_DIR="$HOME/.cache/tinker"

VERSION="7.5-agentic"

log() { echo -e "${BLUE}[tinker]${RESET} $1"; }
success() { echo -e "${GREEN}✓${RESET} $1"; }
warn() { echo -e "${YELLOW}⚠${RESET} $1"; }
error() { echo -e "${RED}✗${RESET} $1"; exit 1; }
step() { echo -e "\n${MAGENTA}${BOLD}▶${RESET} ${BOLD}$1${RESET}\n"; }

detect_system() {
    step "System Detection"
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) error "Unsupported: $ARCH" ;;
    esac
    
    log "OS: $OS | Arch: $ARCH"
    
    if command -v nvidia-smi &>/dev/null 2>&1; then
        GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        [ -n "$GPU" ] && log "GPU: $GPU (not needed for Gemini cloud)"
    fi
    
    SHELL_NAME=$(basename "$SHELL")
    log "Shell: $SHELL_NAME"
    
    success "System ready"
}

install_deps() {
    step "Installing Dependencies"
    
    case "$OS" in
        linux)
            if command -v pacman &>/dev/null; then
                sudo pacman -S --needed --noconfirm python python-pip git curl 2>&1 | grep -v "warning" || true
            elif command -v apt &>/dev/null; then
                sudo apt update -qq && sudo apt install -y python3 python3-pip python3-venv git curl
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y python3 python3-pip git curl
            fi
            ;;
        darwin)
            command -v brew &>/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            brew install python git
            ;;
    esac
    
    success "Dependencies installed"
}

create_dirs() {
    mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$CONFIG_DIR" "$CACHE_DIR"
}

setup_gemini_key() {
    step "Gemini API Key Setup"
    
    clear
    cat << 'EOF'

╔═══════════════════════════════════════════════════════════╗
║            Gemini API Key (Free - No Credit Card)        ║
╚═══════════════════════════════════════════════════════════╝

Get your FREE API key at:
  https://aistudio.google.com/apikey

Free Tier (Gemini 3.8 Flash - default model):
  • ~10-15 requests per minute
  • 1,000-1,500 requests per day
  • 1 MILLION token context window
  • 65K token output

  Note: Google no longer publishes fixed free-tier numbers;
  check your exact quota at https://aistudio.google.com

You can skip this and set later with: tinker key

EOF
    
    echo -e "${BOLD}Gemini API Key:${RESET}"
    read -s -p "Enter Gemini API key (or press Enter to skip): " GEMINI_KEY
    echo ""
    
    if [ -n "$GEMINI_KEY" ]; then
        success "Gemini key saved"
    else
        warn "Gemini key skipped (set later with: tinker key)"
    fi
}

generate_tinker() {
    step "Generating Tinker v7.5 (Enhanced Agentic)"
    
    cat > "$INSTALL_DIR/tinker.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
Tinker v7.5 - Enhanced Agentic Edition
- Fixed Gemini function calling with proper response loop
- Internal to-do list for task tracking
- Smart command execution (safe/elevated/password)
- Gemini 3 model family (3.8 Flash, 3.1 Pro, 3.6 Flash, 3.1 Flash-Lite)
- Enhanced input with readline shortcuts and history
"""

import os
import sys
import json
import subprocess
import getpass
import re
import difflib
import shutil
import time
from pathlib import Path
from typing import List, Dict, Any, Optional, Generator
import argparse

VERSION = "7.5-agentic"

# Try to import prompt_toolkit for enhanced input, fall back to basic input
try:
    from prompt_toolkit import PromptSession
    from prompt_toolkit.history import FileHistory
    from prompt_toolkit.auto_suggest import AutoSuggestFromHistory
    from prompt_toolkit.key_binding import KeyBindings
    from prompt_toolkit.keys import Keys
    from prompt_toolkit.styles import Style
    HAS_PROMPT_TOOLKIT = True
except ImportError:
    HAS_PROMPT_TOOLKIT = False
CONFIG_DIR = Path.home() / ".config" / "tinker"
CACHE_DIR = Path.home() / ".cache" / "tinker"
DEBUG = os.environ.get("TINKER_DEBUG", "0") == "1"

for d in [CONFIG_DIR, CACHE_DIR]:
    d.mkdir(parents=True, exist_ok=True)

DEFAULT_CONFIG = {
    "model": "gemini-3.8-flash",
    "gemini_api_key": "",
    "max_output_tokens": 65536,
    "temperature": 0.7,
    "stream": True,
    "auto_approve": False,
    "max_context_files": 100,
    "token_budget": 1000000,
    "thinking_enabled": True,  # Enable thinking for better reasoning
    "context_compression": "smart",  # full, smart, minimal
    "max_iterations": 0,  # 0 = unlimited iterations (no limit)
}

GEMINI_MODELS = [
    {
        "id": "gemini-3.8-flash",
        "name": "Gemini 3.8 Flash",
        "desc": "Most intelligent Flash model - long-horizon coding & agents, 1M context, 65K output - RECOMMENDED",
        "limits": "~10-15 RPM (free tier, check aistudio.google.com)",
        "rank": 1,
        "use_streaming": True,
    },
    {
        "id": "gemini-3.1-pro-preview",
        "name": "Gemini 3.1 Pro",
        "desc": "Advanced reasoning & complex problem-solving (preview, slower, paid tier only)",
        "limits": "Paid tier only (Pro models removed from free tier)",
        "rank": 2,
        "use_streaming": False,  # Pro works better without streaming
    },
    {
        "id": "gemini-3.6-flash",
        "name": "Gemini 3.6 Flash",
        "desc": "Previous-gen Flash, balances speed and multimodal capability",
        "limits": "~10-15 RPM (free tier, check aistudio.google.com)",
        "rank": 3,
        "use_streaming": True,
    },
    {
        "id": "gemini-3.1-flash-lite",
        "name": "Gemini 3.1 Flash-Lite",
        "desc": "Fastest, most cost-effective, frontier-class performance",
        "limits": "~15+ RPM (free tier, check aistudio.google.com)",
        "rank": 4,
        "use_streaming": True,
    },
]

class Colors:
    BLUE = '\033[0;34m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    CYAN = '\033[0;36m'
    MAGENTA = '\033[0;35m'
    RESET = '\033[0m'
    BOLD = '\033[1m'
    DIM = '\033[2m'

def debug_log(msg: str):
    if DEBUG:
        print(f"{Colors.DIM}[DEBUG] {msg}{Colors.RESET}", file=sys.stderr)

class EnhancedInput:
    """
    Enhanced input handler with readline-like shortcuts:
    - Ctrl+Left/Right: Move by word
    - Ctrl+Backspace: Delete word backward
    - Ctrl+Delete/W: Delete word forward
    - Ctrl+K/U - Delete to end/start of line
    - Shift+Left/Right: Select character
    - Up/Down: History navigation
    - Ctrl+R: Reverse search history
    - Tab: Auto-complete from history
    """
    
    def __init__(self):
        self.history_file = CACHE_DIR / "history"
        self.session = None
        self._init_session()
    
    def _init_session(self):
        if not HAS_PROMPT_TOOLKIT:
            return
        
        # Create custom key bindings for additional shortcuts
        bindings = KeyBindings()
        
        # Ctrl+Backspace to delete word backward (some terminals send ^H or ^?)
        @bindings.add(Keys.ControlH)
        def _(event):
            """Delete word backward on Ctrl+Backspace (some terminals)."""
            buff = event.app.current_buffer
            text = buff.text[:buff.cursor_position]
            # Skip trailing spaces
            while text and text[-1] == ' ':
                text = text[:-1]
                buff.delete_before_cursor(1)
            # Delete until space or start
            while text and text[-1] != ' ':
                text = text[:-1]
                buff.delete_before_cursor(1)
        
        # Style for the prompt - yellow bold for "You:"
        style = Style.from_dict({
            'prompt': 'ansibrightyellow bold',
        })
        
        try:
            self.session = PromptSession(
                history=FileHistory(str(self.history_file)),
                auto_suggest=AutoSuggestFromHistory(),
                key_bindings=bindings,
                style=style,
                enable_history_search=True,  # Ctrl+R for reverse search
                mouse_support=False,
                complete_while_typing=False,
            )
        except Exception as e:
            debug_log(f"Failed to init prompt_toolkit: {e}")
            self.session = None
    
    def get_input(self, prompt_text: str = "You: ") -> str:
        """Get input with enhanced editing capabilities."""
        if self.session:
            try:
                # Use prompt_toolkit with styled prompt (no ANSI codes needed)
                # Strip any ANSI codes that might be in the prompt
                clean_prompt = re.sub(r'\x1b\[[0-9;]*m', '', prompt_text)
                return self.session.prompt(
                    [('class:prompt', clean_prompt)],
                    default='',
                ).strip()
            except (EOFError, KeyboardInterrupt):
                raise
            except Exception as e:
                debug_log(f"prompt_toolkit error: {e}")
                pass
        
        # Fallback to basic input with readline if available
        try:
            import readline
            readline.parse_and_bind(r'"\e[1;5D": backward-word')  # Ctrl+Left
            readline.parse_and_bind(r'"\e[1;5C": forward-word')   # Ctrl+Right
            readline.parse_and_bind(r'"\C-w": backward-kill-word') # Ctrl+W
        except ImportError:
            pass
        
        # Use colored prompt for fallback
        return input(f"{Colors.YELLOW}{prompt_text}{Colors.RESET}").strip()
    
    @staticmethod
    def print_shortcuts():
        """Print available keyboard shortcuts."""
        print(f"""
{Colors.BOLD}Input Shortcuts:{Colors.RESET}
  {Colors.CYAN}Navigation:{Colors.RESET}
    Ctrl+Left/Right  - Move cursor by word
    Home / End       - Move to start/end of line
    Ctrl+A / Ctrl+E  - Move to start/end of line
  
  {Colors.CYAN}Editing:{Colors.RESET}
    Ctrl+W           - Delete word backward
    Ctrl+Backspace   - Delete word backward
    Ctrl+K           - Delete to end of line
    Ctrl+U           - Delete to start of line
  
  {Colors.CYAN}History:{Colors.RESET}
    Up / Down        - Navigate command history
    Ctrl+R           - Reverse search history
    Ctrl+P / Ctrl+N  - Previous/next in history
""")

class Config:
    def __init__(self):
        self.config_file = CONFIG_DIR / "config.json"
        self.config = self.load()
    
    def load(self):
        if self.config_file.exists():
            try:
                with open(self.config_file) as f:
                    return {**DEFAULT_CONFIG, **json.load(f)}
            except (json.JSONDecodeError, UnicodeDecodeError, OSError) as e:
                backup = self.config_file.with_suffix(".json.bak")
                try:
                    shutil.copy(self.config_file, backup)
                except OSError:
                    backup = None
                print(f"{Colors.RED}⚠ config.json is corrupted ({e}). "
                      f"Resetting to defaults.{Colors.RESET}", file=sys.stderr)
                if backup:
                    print(f"{Colors.DIM}  Backed up broken file to {backup}{Colors.RESET}", file=sys.stderr)
                cfg = DEFAULT_CONFIG.copy()
                try:
                    with open(self.config_file, 'w') as f:
                        json.dump(cfg, f, indent=2)
                except OSError:
                    pass
                return cfg
        return DEFAULT_CONFIG.copy()
    
    def save(self):
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f, indent=2)
    
    def get(self, k, default=None):
        return self.config.get(k, default)
    
    def set(self, k, v):
        self.config[k] = v
        self.save()

class SmartContext:
    """
    Compressed context builder using hierarchical summarization.
    
    Strategy:
    1. Level 1: Project structure tree with file descriptions
    2. Level 2: Code signatures (functions, classes, exports) without implementations
    3. Level 3: Full content only for critical config files
    4. Agent uses read_file tool for full content when needed
    """
    
    def __init__(self, project_dir: Path, config: Config):
        self.project_dir = project_dir
        self.config = config
        self.compression_mode = config.get("context_compression", "smart")  # full, smart, minimal
    
    def estimate_tokens(self, text: str) -> int:
        return len(text) // 4
    
    def should_ignore(self, path: Path) -> bool:
        ignore = {'.git', 'node_modules', '__pycache__', '.venv', 'venv', 
                 'dist', 'build', 'target', '.next', 'coverage', '.idea',
                 '.cache', '.pytest_cache', 'eggs', '*.egg-info', '.tox',
                 'htmlcov', '.mypy_cache', '.ruff_cache', 'bower_components'}
        try:
            path_str = str(path.relative_to(self.project_dir))
            return any(p in path_str for p in ignore)
        except ValueError:
            return False
    
    def get_relevant_files(self, max_files: int = 100) -> List[Path]:
        ext = {'.py', '.js', '.ts', '.jsx', '.tsx', '.java', '.cpp', '.go', 
               '.rs', '.rb', '.php', '.sh', '.md', '.json', '.yaml', '.toml', 
               '.html', '.css', '.dart', '.kt', '.swift', '.c', '.h', '.sql',
               '.vue', '.svelte', '.astro', '.prisma', '.graphql', '.proto'}
        
        files = []
        for p in self.project_dir.rglob("*"):
            if p.is_file() and p.suffix in ext and not self.should_ignore(p):
                files.append(p)
        
        files.sort(key=lambda p: self._importance(p), reverse=True)
        return files[:max_files]
    
    def _importance(self, path: Path) -> int:
        n = path.name.lower()
        # Entry points - highest priority
        if n in ['main.py', 'app.py', 'index.js', 'index.ts', 'main.rs', 'main.go', 'mod.rs']: return 100
        # Config files - very important
        if n in ['package.json', 'cargo.toml', 'pyproject.toml', 'go.mod', 'tsconfig.json']: return 95
        if n in ['next.config.js', 'vite.config.ts', 'webpack.config.js', 'tailwind.config.js']: return 90
        if 'readme' in n: return 85
        if 'config' in n or 'settings' in n: return 75
        if n in ['.env.example', 'docker-compose.yml', 'dockerfile']: return 70
        # Schema/types
        if 'schema' in n or 'types' in n or 'interface' in n: return 65
        if 'model' in n or 'entity' in n: return 60
        # Routes/API
        if 'route' in n or 'api' in n or 'handler' in n: return 55
        # Components
        if 'component' in n: return 50
        # Utils/helpers
        if 'util' in n or 'helper' in n or 'lib' in n: return 45
        # Tests - lower priority
        if 'test' in n or 'spec' in n: return 20
        return 40
    
    def extract_code_signatures(self, content: str, file_ext: str) -> str:
        """
        Extract function/class signatures without full implementations.
        This is a lightweight parser - not AST-based but effective.
        """
        lines = content.split('\n')
        signatures = []
        in_docstring = False
        docstring_delim = None
        current_indent = 0
        skip_until_dedent = False
        brace_depth = 0
        
        for i, line in enumerate(lines):
            stripped = line.strip()
            
            # Track docstrings (Python)
            if '"""' in stripped or "'''" in stripped:
                delim = '"""' if '"""' in stripped else "'''"
                if in_docstring:
                    if delim == docstring_delim:
                        in_docstring = False
                        continue
                else:
                    # Check if single-line docstring
                    if stripped.count(delim) >= 2:
                        signatures.append(line)
                        continue
                    in_docstring = True
                    docstring_delim = delim
                    signatures.append(line)
                    continue
            
            if in_docstring:
                # Include docstring content (valuable context)
                if len(signatures) < 500:  # Limit docstring capture
                    signatures.append(line)
                continue
            
            # Python signatures
            if file_ext == '.py':
                if stripped.startswith(('def ', 'async def ', 'class ')):
                    signatures.append(line)
                    # Capture docstring on next lines if present
                elif stripped.startswith(('import ', 'from ')):
                    signatures.append(line)
                elif stripped.startswith('@'):  # Decorators
                    signatures.append(line)
                elif stripped.startswith(('#', 'TODO', 'FIXME', 'NOTE')):
                    if len(stripped) > 5:
                        signatures.append(line)
            
            # JavaScript/TypeScript signatures
            elif file_ext in ['.js', '.ts', '.jsx', '.tsx']:
                if any(stripped.startswith(p) for p in [
                    'import ', 'export ', 'function ', 'async function ',
                    'const ', 'let ', 'var ', 'class ', 'interface ', 'type ',
                    'export default', 'export const', 'export function',
                    'export interface', 'export type', 'export class',
                    '//', '/*', ' *'  # Comments
                ]):
                    # For const/let/var, only capture if it's a function or important
                    if stripped.startswith(('const ', 'let ', 'var ')):
                        if '=>' in stripped or 'function' in stripped or '=' not in stripped:
                            signatures.append(line)
                        elif any(x in stripped for x in ['Component', 'Hook', 'Context', 'Provider', 'Router']):
                            signatures.append(line)
                    else:
                        signatures.append(line)
            
            # Go signatures
            elif file_ext == '.go':
                if any(stripped.startswith(p) for p in [
                    'package ', 'import ', 'func ', 'type ', 'const ', 'var ',
                    '//', '/*'
                ]):
                    signatures.append(line)
            
            # Rust signatures  
            elif file_ext == '.rs':
                if any(stripped.startswith(p) for p in [
                    'use ', 'mod ', 'pub ', 'fn ', 'async fn ', 'struct ', 
                    'enum ', 'impl ', 'trait ', '//', '//!'
                ]):
                    signatures.append(line)
            
            # For config files, include more content
            elif file_ext in ['.json', '.yaml', '.toml', '.yml']:
                # Include first 50 lines of config files
                if i < 50:
                    signatures.append(line)
        
        return '\n'.join(signatures)
    
    def get_file_summary(self, path: Path) -> Dict[str, Any]:
        """Get a summary of a file including its signatures."""
        try:
            content = path.read_text(encoding='utf-8', errors='ignore')
            lines = len(content.splitlines())
            chars = len(content)
            
            # For small files, include full content
            if chars < 500:
                return {
                    "path": str(path.relative_to(self.project_dir)),
                    "lines": lines,
                    "chars": chars,
                    "content_type": "full",
                    "content": content
                }
            
            # For larger files, extract signatures
            signatures = self.extract_code_signatures(content, path.suffix)
            sig_lines = len(signatures.splitlines()) if signatures else 0
            
            return {
                "path": str(path.relative_to(self.project_dir)),
                "lines": lines,
                "chars": chars,
                "content_type": "signatures",
                "signatures": signatures,
                "compression_ratio": f"{sig_lines}/{lines} lines ({100*sig_lines//max(1,lines)}%)"
            }
        except Exception as e:
            return {
                "path": str(path.relative_to(self.project_dir)),
                "error": str(e)
            }
    
    def build_project_tree(self) -> str:
        """Build a visual tree of the project structure."""
        tree_lines = []
        
        def add_dir(dir_path: Path, prefix: str = "", is_last: bool = True):
            try:
                items = sorted([p for p in dir_path.iterdir() if not self.should_ignore(p)])
            except:
                return
            
            dirs = [p for p in items if p.is_dir()]
            files = [p for p in items if p.is_file()]
            
            # Show files first
            for i, f in enumerate(files):
                is_last_item = (i == len(files) - 1) and (len(dirs) == 0)
                connector = "└── " if is_last_item else "├── "
                tree_lines.append(f"{prefix}{connector}{f.name}")
            
            # Then directories
            for i, d in enumerate(dirs):
                is_last_dir = i == len(dirs) - 1
                connector = "└── " if is_last_dir else "├── "
                tree_lines.append(f"{prefix}{connector}{d.name}/")
                extension = "    " if is_last_dir else "│   "
                add_dir(d, prefix + extension, is_last_dir)
        
        tree_lines.append(f"{self.project_dir.name}/")
        add_dir(self.project_dir)
        
        return '\n'.join(tree_lines[:200])  # Limit tree size
    
    def build_context(self, max_tokens: int = 1000000) -> str:
        """
        Build compressed context using hierarchical summarization.
        """
        mode = self.compression_mode
        
        if mode == "full":
            return self._build_full_context(max_tokens)
        elif mode == "minimal":
            return self._build_minimal_context()
        else:  # smart (default)
            return self._build_smart_context(max_tokens)
    
    def _build_full_context(self, max_tokens: int) -> str:
        """Original full context mode (for comparison)."""
        files = self.get_relevant_files(self.config.get("max_context_files", 100))
        parts = []
        tokens = 0
        count = 0
        
        for f in files:
            try:
                content = f.read_text(encoding='utf-8', errors='ignore')
                rel = f.relative_to(self.project_dir)
                header = f"\n--- {rel} ---\n"
                t = self.estimate_tokens(header + content)
                
                if tokens + t > max_tokens: break
                
                parts.append(header + content)
                tokens += t
                count += 1
            except: continue
        
        return f"Project: {self.project_dir.name}\nFiles: {count} | ~{tokens:,} tokens\n\n" + "".join(parts)
    
    def _build_minimal_context(self) -> str:
        """Minimal context - just project tree and entry points."""
        tree = self.build_project_tree()
        return f"""# Project: {self.project_dir.name}

## Structure
```
{tree}
```

## Instructions
This is a minimal context view. Use `read_file` to examine any file you need.
Use `search_code` to find specific patterns across the codebase.
"""
    
    def _build_smart_context(self, max_tokens: int) -> str:
        """
        Smart compressed context with hierarchical information.
        Compression typically achieves 5-10x reduction while preserving understanding.
        """
        files = self.get_relevant_files(self.config.get("max_context_files", 100))
        
        # Section 1: Project tree
        tree = self.build_project_tree()
        
        # Section 2: Config files (full content - they're usually small and critical)
        config_section = []
        config_files = ['package.json', 'tsconfig.json', 'pyproject.toml', 'cargo.toml', 
                       'go.mod', 'requirements.txt', 'next.config.js', 'vite.config.ts']
        
        for f in files:
            if f.name.lower() in config_files:
                try:
                    content = f.read_text(encoding='utf-8', errors='ignore')
                    if len(content) < 5000:  # Only if reasonably sized
                        rel = f.relative_to(self.project_dir)
                        config_section.append(f"\n### {rel}\n```\n{content}\n```")
                except:
                    pass
        
        # Section 3: Code signatures for all files
        code_section = []
        tokens_used = self.estimate_tokens(tree + ''.join(config_section))
        remaining_budget = max_tokens - tokens_used - 2000  # Reserve for formatting
        
        for f in files:
            if f.name.lower() in config_files:
                continue  # Already included in full
            
            summary = self.get_file_summary(f)
            
            if summary.get("content_type") == "full":
                entry = f"\n### {summary['path']} ({summary['lines']} lines) [FULL]\n```\n{summary['content']}\n```"
            elif summary.get("signatures"):
                entry = f"\n### {summary['path']} ({summary['compression_ratio']})\n```\n{summary['signatures']}\n```"
            else:
                entry = f"\n### {summary['path']} ({summary.get('lines', '?')} lines) - Use read_file for content"
            
            entry_tokens = self.estimate_tokens(entry)
            if tokens_used + entry_tokens > remaining_budget:
                code_section.append(f"\n... and {len(files) - len(code_section)} more files. Use read_file to examine them.")
                break
            
            code_section.append(entry)
            tokens_used += entry_tokens
        
        total_tokens = self.estimate_tokens(tree + ''.join(config_section) + ''.join(code_section))
        original_estimate = sum(self.estimate_tokens(f.read_text(errors='ignore')) for f in files[:50] if f.exists())
        compression_ratio = f"{100 - (100 * total_tokens // max(1, original_estimate))}%" if original_estimate > 0 else "N/A"
        
        return f"""# Project: {self.project_dir.name}
## Context Mode: Smart Compressed (~{total_tokens:,} tokens, {compression_ratio} smaller)

**IMPORTANT**: This is a compressed view showing code signatures and structure.
- Use `read_file(path)` to get full file contents when needed
- Use `search_code(pattern)` to find specific code patterns
- Config files are shown in full below

## Project Structure
```
{tree}
```

## Configuration Files
{''.join(config_section) if config_section else 'No standard config files found.'}

## Code Signatures (functions, classes, exports)
{''.join(code_section)}
"""

class TodoList:
    """Enhanced to-do list for agent task tracking with full CRUD operations"""
    
    def __init__(self):
        self.tasks = []  # List of {"id": int, "task": str, "status": "pending"|"done"|"skipped"|"in_progress"}
        self.next_id = 1
        self.current_task_id = None  # Track which task is currently being worked on
    
    def add(self, task: str, after_id: int = None) -> int:
        """Add a task. If after_id is provided, insert after that task."""
        task_id = self.next_id
        new_task = {"id": task_id, "task": task, "status": "pending"}
        self.next_id += 1
        
        if after_id is not None:
            # Find position after the specified task
            for i, t in enumerate(self.tasks):
                if t["id"] == after_id:
                    self.tasks.insert(i + 1, new_task)
                    return task_id
        
        # Default: append to end
        self.tasks.append(new_task)
        return task_id
    
    def add_multiple(self, tasks: List[str], after_id: int = None) -> List[int]:
        """Add multiple tasks, optionally after a specific task."""
        ids = []
        insert_after = after_id
        for task in tasks:
            new_id = self.add(task, insert_after)
            ids.append(new_id)
            insert_after = new_id  # Chain insertions
        return ids
    
    def update(self, task_id: int, new_description: str) -> bool:
        """Update a task's description."""
        for t in self.tasks:
            if t["id"] == task_id:
                t["task"] = new_description
                return True
        return False
    
    def start(self, task_id: int) -> bool:
        """Mark a task as in progress."""
        for t in self.tasks:
            if t["id"] == task_id:
                t["status"] = "in_progress"
                self.current_task_id = task_id
                return True
        return False
    
    def complete(self, task_id: int) -> bool:
        """Mark a task as done."""
        for t in self.tasks:
            if t["id"] == task_id:
                t["status"] = "done"
                if self.current_task_id == task_id:
                    self.current_task_id = None
                return True
        return False
    
    def skip(self, task_id: int, reason: str = None) -> bool:
        """Skip a task, optionally with a reason."""
        for t in self.tasks:
            if t["id"] == task_id:
                t["status"] = "skipped"
                if reason:
                    t["skip_reason"] = reason
                if self.current_task_id == task_id:
                    self.current_task_id = None
                return True
        return False
    
    def remove(self, task_id: int) -> bool:
        """Remove a task entirely."""
        for i, t in enumerate(self.tasks):
            if t["id"] == task_id:
                self.tasks.pop(i)
                if self.current_task_id == task_id:
                    self.current_task_id = None
                return True
        return False
    
    def clear(self) -> int:
        """Clear all tasks and reset. Returns count of cleared tasks."""
        count = len(self.tasks)
        self.tasks = []
        self.next_id = 1
        self.current_task_id = None
        return count
    
    def get_pending(self) -> List[Dict]:
        return [t for t in self.tasks if t["status"] == "pending"]
    
    def get_in_progress(self) -> List[Dict]:
        return [t for t in self.tasks if t["status"] == "in_progress"]
    
    def get_all(self) -> List[Dict]:
        return self.tasks.copy()
    
    def get_next_pending(self) -> Optional[Dict]:
        """Get the next pending task."""
        for t in self.tasks:
            if t["status"] == "pending":
                return t
        return None
    
    def format_list(self) -> str:
        if not self.tasks:
            return "No tasks in to-do list"
        
        lines = []
        for t in self.tasks:
            if t["status"] == "done":
                mark = "✓"
            elif t["status"] == "skipped":
                mark = "○"
            elif t["status"] == "in_progress":
                mark = "▶"
            else:
                mark = "☐"
            
            skip_info = f" (skipped: {t.get('skip_reason', 'no reason')})" if t["status"] == "skipped" and t.get("skip_reason") else ""
            lines.append(f"  {mark} [{t['id']}] {t['task']}{skip_info}")
        
        pending = len([t for t in self.tasks if t["status"] == "pending"])
        done = len([t for t in self.tasks if t["status"] == "done"])
        in_progress = len([t for t in self.tasks if t["status"] == "in_progress"])
        
        status = f"To-Do List ({done}/{len(self.tasks)} done"
        if in_progress:
            status += f", {in_progress} in progress"
        if pending:
            status += f", {pending} pending"
        status += "):"
        
        return status + "\n" + "\n".join(lines)

class MCPTools:
    """MCP tools with multi-directory support and task tracking"""
    
    def __init__(self, project_dir: Path, context: SmartContext):
        self.project_dir = project_dir
        self.context = context
        self.tools = self._register()
        self.files_created = set()  # Track files created this session
        self.files_writing = {}  # Track files being written in chunks: {path: content_so_far}
        self.todo = TodoList()  # Internal to-do list for agent
        self.background_processes = []  # Track background processes
    
    def _register(self):
        return {
            "read_file": {"desc": "Read FULL file content (for editing)", "fn": self.read_file},
            "peek_file": {"desc": "Quick peek at file summary (for browsing)", "fn": self.peek_file},
            "write_file": {"desc": "Write/create file", "fn": self.write_file},
            "list_files": {"desc": "List directory contents", "fn": self.list_files},
            "search_code": {"desc": "Search for patterns in code", "fn": self.search_code},
            "execute_command": {"desc": "Execute shell command", "fn": self.exec_cmd},
            "run_tests": {"desc": "Run project tests", "fn": self.run_tests},
            "web_search": {"desc": "Search the web for information", "fn": self.web_search},
            # Enhanced to-do list tools
            "todo_add": {"desc": "Add tasks to to-do list", "fn": self.todo_add},
            "todo_update": {"desc": "Update a task description", "fn": self.todo_update},
            "todo_start": {"desc": "Mark a task as in progress", "fn": self.todo_start},
            "todo_done": {"desc": "Mark a task as complete", "fn": self.todo_done},
            "todo_skip": {"desc": "Skip a task with reason", "fn": self.todo_skip},
            "todo_clear": {"desc": "Clear all tasks for new workflow", "fn": self.todo_clear},
            "todo_list": {"desc": "Show current to-do list status", "fn": self.todo_list},
            "task_complete": {"desc": "Signal task completion", "fn": self.task_complete},
        }
    
    def get_schemas(self):
        return [{"name": n, "description": t["desc"]} for n, t in self.tools.items()]
    
    def execute(self, name: str, params: Dict, auto: bool = False) -> str:
        if name not in self.tools: 
            return f"Unknown tool: {name}"
        try:
            return self.tools[name]["fn"](params, auto)
        except Exception as e:
            return f"Error: {e}"
    
    def resolve_path(self, path_str: str) -> Path:
        path = Path(path_str).expanduser()
        if not path.is_absolute():
            rel_path = self.project_dir / path
            if rel_path.exists():
                return rel_path
            cwd_path = Path.cwd() / path
            if cwd_path.exists():
                return cwd_path
            return rel_path
        return path
    
    def read_file(self, p: Dict, auto: bool) -> str:
        """
        Read FULL file content. Use this when you need to EDIT a file.
        Always returns complete content - no truncation.
        For browsing/context, use peek_file instead.
        """
        file_path = p.get('path') or p.get('file_path') or p.get('filePath')
        start_line = p.get('start_line') or p.get('start')
        end_line = p.get('end_line') or p.get('end')
        max_size_mb = 10  # 10MB limit for full reads
        
        if not file_path:
            return f"Error: Missing path parameter"
        
        try:
            path = self.resolve_path(file_path)
            if not path.exists():
                return f"Error: File not found: {file_path}"
            
            # Check file size first
            file_size = path.stat().st_size
            file_size_mb = file_size / (1024 * 1024)
            
            if file_size_mb > max_size_mb:
                return f"Error: File too large ({file_size_mb:.1f}MB > {max_size_mb}MB limit). Use start_line/end_line to read specific ranges, or peek_file for summary."
            
            # Read with encoding detection
            content = None
            try:
                content = path.read_text(encoding='utf-8', errors='replace')
            except UnicodeDecodeError:
                # Try other common encodings
                for enc in ['latin-1', 'cp1252', 'iso-8859-1']:
                    try:
                        content = path.read_text(encoding=enc, errors='replace')
                        break
                    except:
                        continue
                else:
                    return f"Error: Could not decode {file_path} with any supported encoding"
            
            if content is None:
                return f"Error: Failed to read {file_path}"
            
            total_lines = len(content.splitlines())
            lines = content.splitlines(keepends=True)
            
            # Handle line range requests (useful for very large files)
            if start_line is not None or end_line is not None:
                try:
                    start = int(start_line) if start_line is not None else 1
                    end = int(end_line) if end_line is not None else total_lines
                    # Convert to 0-based indexing
                    start_idx = max(0, start - 1)
                    end_idx = min(len(lines), end)
                    selected_lines = lines[start_idx:end_idx]
                    selected_content = ''.join(selected_lines)
                    return f"[{total_lines} total lines, showing {start}-{end}]\n{selected_content}"
                except (ValueError, IndexError) as e:
                    return f"Error: Invalid line range: {e}"
            
            # Validate we got the full content
            if len(content) != file_size:
                # This shouldn't happen with text mode, but check anyway
                debug_log(f"Warning: Content length {len(content)} != file size {file_size}")
            
            # Always return full content for editing
            result = f"[{total_lines} lines]\n{content}"
            
            # Verify result isn't too large (safety check)
            if len(result) > 50_000_000:  # 50MB limit
                return f"Error: File content too large ({len(result):,} chars). Use start_line/end_line to read in chunks, or peek_file for summary."
            
            return result
            
        except MemoryError:
            return f"Error: File too large to read into memory. Use start_line/end_line to read specific ranges, or peek_file for summary."
        except PermissionError:
            return f"Error: Permission denied reading {file_path}"
        except OSError as e:
            return f"Error: OS error reading {file_path}: {e}"
        except Exception as e:
            import traceback
            debug_log(f"read_file exception: {traceback.format_exc()}")
            return f"Error reading {file_path}: {type(e).__name__}: {e}"
    
    def peek_file(self, p: Dict, auto: bool) -> str:
        """
        Quick peek at file - returns summary with first/last lines.
        Use this for browsing/context. Use read_file for full content when editing.
        """
        file_path = p.get('path') or p.get('file_path') or p.get('filePath')
        preview_lines = p.get('preview_lines', 50)  # Lines to show from start/end
        
        if not file_path:
            return f"Error: Missing path parameter"
        
        try:
            path = self.resolve_path(file_path)
            if not path.exists():
                return f"File not found: {file_path}"
            
            # Get file size first
            file_size = path.stat().st_size
            
            # Read with encoding detection
            try:
                content = path.read_text(encoding='utf-8', errors='replace')
            except UnicodeDecodeError:
                for enc in ['latin-1', 'cp1252', 'iso-8859-1']:
                    try:
                        content = path.read_text(encoding=enc, errors='replace')
                        break
                    except:
                        continue
                else:
                    return f"Error: Could not decode {file_path} with any supported encoding"
            
            total_lines = len(content.splitlines())
            lines = content.splitlines(keepends=True)
            chars = len(content)
            
            # For small files, just return basic info
            if total_lines <= preview_lines * 2:
                return f"[{total_lines} lines, {chars:,} chars]\n{content}"
            
            # For larger files, show summary
            first_lines = ''.join(lines[:preview_lines])
            last_lines = ''.join(lines[-preview_lines:])
            
            summary = f"""File: {path.name}
Size: {file_size:,} bytes ({chars:,} chars)
Lines: {total_lines:,}

--- First {preview_lines} lines ---
{first_lines}
...
--- Last {preview_lines} lines ---
{last_lines}

💡 Use read_file(path="{file_path}") to read full content for editing."""
            return summary
            
        except MemoryError:
            return f"Error: File too large. Use read_file with start_line/end_line to read specific ranges."
        except Exception as e:
            return f"Error peeking {file_path}: {e}"
    
    def write_file(self, p: Dict, auto: bool) -> str:
        file_path = p.get('path') or p.get('file_path') or p.get('filePath')
        file_content = p.get('content') or p.get('file_content') or p.get('fileContent')
        mode = p.get('mode', 'overwrite').lower()  # 'overwrite' or 'append'
        finalize = p.get('finalize', True)  # If False, accumulate chunks
        
        if not file_path:
            return f"Error: Missing path parameter. Got keys: {list(p.keys())}"
        if file_content is None:
            return f"Error: Missing content parameter. Got keys: {list(p.keys())}"
        
        try:
            path = self.resolve_path(file_path)
            path.parent.mkdir(parents=True, exist_ok=True)
            
            # Check if we have accumulated chunks for this file
            if str(path) in self.files_writing:
                # Add current chunk to accumulated content
                self.files_writing[str(path)] += file_content
                accumulated = self.files_writing[str(path)]
                
                if finalize:
                    # Final chunk - write all accumulated content
                    if mode == 'append' and path.exists():
                        existing = path.read_text(encoding='utf-8')
                        path.write_text(existing + accumulated, encoding='utf-8')
                    else:
                        path.write_text(accumulated, encoding='utf-8')
                    del self.files_writing[str(path)]
                    self.files_created.add(str(path))
                    lines = len(accumulated.splitlines())
                    chars = len(accumulated)
                    return f"✓ Written (chunked): {path.name} ({lines} lines, {chars} chars)"
                else:
                    # More chunks coming
                    lines = len(accumulated.splitlines())
                    chars = len(accumulated)
                    return f"✓ Chunk appended: {path.name} ({lines} lines, {chars} chars so far)"
            
            # No accumulated chunks - handle as single write or start accumulation
            if not finalize:
                # Start accumulating chunks
                self.files_writing[str(path)] = file_content
                lines = len(file_content.splitlines())
                chars = len(file_content)
                return f"✓ Chunk 1 written: {path.name} ({lines} lines, {chars} chars so far)"
            else:
                # Single write (standard mode)
                if mode == 'append' and path.exists():
                    existing = path.read_text(encoding='utf-8')
                    path.write_text(existing + file_content, encoding='utf-8')
                else:
                    path.write_text(file_content, encoding='utf-8')
                self.files_created.add(str(path))
                # Clear any stale accumulated chunks if present
                if str(path) in self.files_writing:
                    del self.files_writing[str(path)]
                lines = len(file_content.splitlines())
                chars = len(file_content)
                return f"✓ Written: {path.name} ({lines} lines, {chars} chars)"
        except Exception as e:
            # Clean up on error
            if str(path) in self.files_writing:
                del self.files_writing[str(path)]
            return f"Error writing {file_path}: {e}"
    
    def list_files(self, p: Dict, auto: bool) -> str:
        dir_path = self.resolve_path(p.get("directory_path", "."))
        if not dir_path.is_dir():
            return f"Not a directory: {p.get('directory_path')}"
        
        try:
            files = []
            for item in sorted(dir_path.iterdir()):
                if item.name.startswith('.'):
                    continue
                if item.is_file():
                    files.append(str(item.relative_to(dir_path)))
                elif item.is_dir():
                    files.append(str(item.relative_to(dir_path)) + "/")
            
            return f"Files in {dir_path}:\n" + "\n".join(files[:100])
        except Exception as e:
            return f"Error listing {dir_path}: {e}"
    
    def search_code(self, p: Dict, auto: bool) -> str:
        pattern = p.get("pattern") or p.get("search_term")
        if not pattern:
            return "Error: Missing pattern parameter"
        try:
            r = subprocess.run(
                ["grep", "-r", "-n", "-i", pattern, "."],
                cwd=self.project_dir,
                capture_output=True,
                text=True,
                timeout=10
            )
            if r.stdout:
                lines = r.stdout.strip().split('\n')
                return f"Found {len(lines)} matches:\n{r.stdout[:3000]}"
            return f"No matches for '{pattern}'"
        except Exception as e:
            return f"Search error: {e}"
    
    def exec_cmd(self, p: Dict, auto: bool) -> str:
        cmd = p.get("command")
        if not cmd:
            return "Error: Missing command parameter"
        
        # Categorize command types
        # 1. Safe commands - run in background, no prompt
        safe_patterns = [
            'ls', 'cat', 'head', 'tail', 'grep', 'find', 'echo', 'pwd', 'whoami',
            'date', 'which', 'type', 'file', 'wc', 'sort', 'uniq', 'diff',
            'python', 'python3', 'node', 'npm run', 'cargo run', 'go run',
            'git status', 'git log', 'git diff', 'git branch',
        ]
        
        # 2. Elevated privilege commands - need approval
        elevated_patterns = [
            'rm -rf', 'rm -r', 'chmod 777', 'chown', 'dd if=', 'mkfs',
            '> /dev/', 'curl.*|.*sh', 'wget.*|.*sh', 'mv /', 'cp /',
        ]
        
        # 3. Password-required commands - need interactive terminal
        password_patterns = [
            'sudo', 'apt install', 'apt upgrade', 'apt remove',
            'dnf install', 'dnf upgrade', 'dnf remove',
            'pacman -S', 'pacman -R', 'pacman -Syu',
            'yum install', 'brew install', 'pip install --user',
        ]
        
        cmd_lower = cmd.lower().strip()
        
        # Check command category
        is_safe = any(cmd_lower.startswith(p) or f' {p}' in cmd_lower for p in safe_patterns)
        is_elevated = any(p in cmd_lower for p in elevated_patterns)
        needs_password = any(p in cmd_lower for p in password_patterns)
        
        # Handle elevated privilege commands
        if is_elevated and not auto:
            print(f"\n{Colors.YELLOW}{'━' * 50}{Colors.RESET}")
            print(f"{Colors.YELLOW}⚠ Elevated privilege command:{Colors.RESET}")
            print(f"  {Colors.CYAN}{cmd}{Colors.RESET}")
            print(f"{Colors.YELLOW}{'━' * 50}{Colors.RESET}")
            response = input(f"{Colors.YELLOW}Execute? [y/N]: {Colors.RESET}").lower()
            if response != 'y':
                return "Command cancelled by user"
        
        # Handle password-required commands (interactive)
        if needs_password:
            print(f"\n{Colors.CYAN}{'━' * 50}{Colors.RESET}")
            print(f"{Colors.CYAN}Command requires authentication:{Colors.RESET}")
            print(f"  {Colors.BOLD}{cmd}{Colors.RESET}")
            print(f"{Colors.CYAN}{'━' * 50}{Colors.RESET}")
            
            if not auto:
                response = input(f"{Colors.YELLOW}Run interactively? [y/N]: {Colors.RESET}").lower()
                if response != 'y':
                    return "Command cancelled by user"
            
            # Run interactively so user can enter password
            try:
                print(f"{Colors.DIM}Running (may prompt for password)...{Colors.RESET}")
                r = subprocess.run(
                    cmd, shell=True, cwd=self.project_dir,
                    timeout=300  # 5 min for package installs
                )
                if r.returncode == 0:
                    return f"Exit code: 0\nCommand completed successfully"
                else:
                    return f"Exit code: {r.returncode}\nCommand finished with errors"
            except subprocess.TimeoutExpired:
                return "Command timed out (300s)"
            except Exception as e:
                return f"Execution error: {e}"
        
        # Safe commands or approved elevated - run normally
        try:
            # For safe commands, don't show verbose output unless debug
            r = subprocess.run(
                cmd, shell=True, cwd=self.project_dir,
                capture_output=True, text=True, timeout=60
            )
            result = f"Exit code: {r.returncode}\n"
            if r.stdout:
                result += f"Output:\n{r.stdout[:2000]}\n"
            if r.stderr and r.returncode != 0:
                result += f"Stderr:\n{r.stderr[:1000]}\n"
            return result
        except subprocess.TimeoutExpired:
            return "Command timed out (60s)"
        except Exception as e:
            return f"Execution error: {e}"
    
    def run_tests(self, p: Dict, auto: bool) -> str:
        fw = p.get("framework")
        if not fw:
            if (self.project_dir / "pytest.ini").exists(): fw = "pytest"
            elif (self.project_dir / "package.json").exists(): fw = "npm"
            elif (self.project_dir / "Cargo.toml").exists(): fw = "cargo"
        
        cmds = {"pytest": "pytest -v", "npm": "npm test", "cargo": "cargo test", "go": "go test ./..."}
        cmd = cmds.get(fw, "pytest -v")
        return self.exec_cmd({"command": cmd}, True)
    
    def web_search(self, p: Dict, auto: bool) -> str:
        """Search the web using DuckDuckGo HTML search"""
        query = p.get("query") or p.get("search_term") or p.get("q")
        if not query:
            return "Error: No search query provided"
        
        try:
            import requests
            from urllib.parse import quote_plus
            
            # Try DuckDuckGo HTML lite (more reliable than instant answer API)
            url = f"https://html.duckduckgo.com/html/?q={quote_plus(query)}"
            
            r = requests.get(url, timeout=15, headers={
                "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
            })
            r.raise_for_status()
            
            # Parse results from HTML
            results = []
            html = r.text
            
            # Extract result snippets (simple regex parsing)
            import re
            
            # Find result links and snippets
            pattern = r'<a[^>]+class="result__a"[^>]*href="([^"]*)"[^>]*>([^<]*)</a>'
            snippet_pattern = r'<a[^>]+class="result__snippet"[^>]*>([^<]*(?:<[^>]+>[^<]*)*)</a>'
            
            links = re.findall(pattern, html)
            snippets = re.findall(r'class="result__snippet"[^>]*>(.+?)</a>', html, re.DOTALL)
            
            # Clean snippets
            def clean_html(text):
                text = re.sub(r'<[^>]+>', '', text)
                text = text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
                text = text.replace('&quot;', '"').replace('&#x27;', "'").replace('&nbsp;', ' ')
                return ' '.join(text.split())[:300]
            
            for i, (url, title) in enumerate(links[:5]):
                result = f"\n{i+1}. **{clean_html(title)}**"
                if i < len(snippets):
                    result += f"\n   {clean_html(snippets[i])}"
                result += f"\n   {url}"
                results.append(result)
            
            if results:
                return f"Search results for '{query}':\n" + "\n".join(results)
            else:
                # Final fallback
                return f"Search completed but no results parsed. Try directly:\nhttps://duckduckgo.com/?q={quote_plus(query)}"
        
        except Exception as e:
            from urllib.parse import quote_plus
            return f"Search error: {e}\nTry manually: https://duckduckgo.com/?q={quote_plus(query)}"
    
    def todo_add(self, p: Dict, auto: bool) -> str:
        """Add tasks to the internal to-do list, optionally after a specific task"""
        tasks = p.get("tasks", [])
        task = p.get("task")  # Single task support
        after_id = p.get("after_id") or p.get("after")  # Insert after specific task
        
        if task and not tasks:
            tasks = [task]
        
        if not tasks:
            return "Error: No tasks provided. Use 'tasks' (array) or 'task' (string)"
        
        ids = self.todo.add_multiple(tasks, after_id=int(after_id) if after_id else None)
        
        # Show the updated list
        print(f"\n{Colors.DIM}{self.todo.format_list()}{Colors.RESET}")
        
        position = f" after task {after_id}" if after_id else ""
        return f"Added {len(ids)} task(s){position}: {ids}"
    
    def todo_update(self, p: Dict, auto: bool) -> str:
        """Update a task's description"""
        task_id = p.get("task_id") or p.get("id")
        new_description = p.get("description") or p.get("task") or p.get("new_description")
        
        if task_id is None:
            return "Error: No task_id provided"
        if not new_description:
            return "Error: No description provided"
        
        if self.todo.update(int(task_id), new_description):
            print(f"\n{Colors.DIM}{self.todo.format_list()}{Colors.RESET}")
            return f"✓ Task {task_id} updated"
        else:
            return f"Error: Task {task_id} not found"
    
    def todo_start(self, p: Dict, auto: bool) -> str:
        """Mark a task as in progress"""
        task_id = p.get("task_id") or p.get("id")
        
        if task_id is None:
            return "Error: No task_id provided"
        
        if self.todo.start(int(task_id)):
            print(f"\n{Colors.DIM}{self.todo.format_list()}{Colors.RESET}")
            return f"▶ Task {task_id} started"
        else:
            return f"Error: Task {task_id} not found"
    
    def todo_done(self, p: Dict, auto: bool) -> str:
        """Mark a task as complete"""
        task_id = p.get("task_id") or p.get("id")
        
        if task_id is None:
            return "Error: No task_id provided"
        
        if self.todo.complete(int(task_id)):
            print(f"\n{Colors.DIM}{self.todo.format_list()}{Colors.RESET}")
            return f"✓ Task {task_id} marked as done"
        else:
            return f"Error: Task {task_id} not found"
    
    def todo_skip(self, p: Dict, auto: bool) -> str:
        """Skip a task with optional reason"""
        task_id = p.get("task_id") or p.get("id")
        reason = p.get("reason")
        
        if task_id is None:
            return "Error: No task_id provided"
        
        if self.todo.skip(int(task_id), reason):
            print(f"\n{Colors.DIM}{self.todo.format_list()}{Colors.RESET}")
            reason_text = f" (reason: {reason})" if reason else ""
            return f"○ Task {task_id} skipped{reason_text}"
        else:
            return f"Error: Task {task_id} not found"
    
    def todo_clear(self, p: Dict, auto: bool) -> str:
        """Clear all tasks to start a new workflow"""
        count = self.todo.clear()
        return f"✓ Cleared {count} task(s). Ready for new workflow."
    
    def todo_list(self, p: Dict, auto: bool) -> str:
        """Show the current to-do list"""
        formatted = self.todo.format_list()
        print(f"\n{Colors.DIM}{formatted}{Colors.RESET}")
        return formatted
    
    def task_complete(self, p: Dict, auto: bool) -> str:
        """Signal that all tasks are complete"""
        summary = p.get("summary", "Task completed")
        # Include to-do summary if there are tasks
        if self.todo.tasks:
            todo_summary = self.todo.format_list()
            return f"TASK_COMPLETE: {summary}\n\n{todo_summary}"
        return f"TASK_COMPLETE: {summary}"

# Gemini function declarations
FUNCTION_DECLARATIONS = [
    {
        "name": "read_file",
        "description": "Read FULL file content. Use this when you need to EDIT a file. Always returns complete content - no truncation. For browsing/context without editing, use peek_file instead.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File path to read"},
                "start_line": {"type": "integer", "description": "Optional: Start line number (1-based). Use with end_line to read a specific range of a very large file."},
                "end_line": {"type": "integer", "description": "Optional: End line number (1-based). Use with start_line to read a specific range."}
            },
            "required": ["path"]
        }
    },
    {
        "name": "peek_file",
        "description": "Quick peek at file - returns summary with first/last lines. Use this for browsing/exploring files to understand structure. When you need to edit a file, use read_file to get full content.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File path to peek at"},
                "preview_lines": {"type": "integer", "description": "Optional: Number of lines to show from start/end (default: 50)"}
            },
            "required": ["path"]
        }
    },
    {
        "name": "write_file",
        "description": "Write content to a file. For small files, write complete content in one call. For large files (>10K chars), use chunked writes: call multiple times with finalize=false, then once with finalize=true for the last chunk.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File path to write"},
                "content": {"type": "string", "description": "File content (or chunk for large files)"},
                "mode": {"type": "string", "description": "Write mode: 'overwrite' (default) or 'append' to append to existing file"},
                "finalize": {"type": "boolean", "description": "If false, accumulate chunks. Set true on last chunk to write file. Default: true"}
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "list_files",
        "description": "List files and directories in a path",
        "parameters": {
            "type": "object",
            "properties": {"directory_path": {"type": "string", "description": "Directory to list"}},
            "required": ["directory_path"]
        }
    },
    {
        "name": "search_code",
        "description": "Search for a pattern in the codebase",
        "parameters": {
            "type": "object",
            "properties": {"pattern": {"type": "string", "description": "Search pattern"}},
            "required": ["pattern"]
        }
    },
    {
        "name": "execute_command",
        "description": "Execute a shell command. Safe commands run automatically. Elevated commands need approval. Package installs run interactively for password entry.",
        "parameters": {
            "type": "object",
            "properties": {"command": {"type": "string", "description": "Shell command to execute"}},
            "required": ["command"]
        }
    },
    {
        "name": "run_tests",
        "description": "Run the project's test suite",
        "parameters": {
            "type": "object",
            "properties": {"framework": {"type": "string", "description": "Test framework (pytest, npm, cargo, go)"}},
            "required": []
        }
    },
    {
        "name": "web_search",
        "description": "Search the web for information, documentation, or solutions. Use this when you need current information or to look up APIs, libraries, error messages, etc.",
        "parameters": {
            "type": "object",
            "properties": {"query": {"type": "string", "description": "Search query"}},
            "required": ["query"]
        }
    },
    {
        "name": "todo_add",
        "description": "Add tasks to your to-do list. Use at start of complex tasks AND mid-task when you discover additional work needed. Can insert after a specific task.",
        "parameters": {
            "type": "object",
            "properties": {
                "tasks": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "List of task descriptions to add"
                },
                "after_id": {
                    "type": "integer",
                    "description": "Optional: Insert tasks after this task ID (for mid-task additions)"
                }
            },
            "required": ["tasks"]
        }
    },
    {
        "name": "todo_update",
        "description": "Update a task's description if scope changes or needs clarification",
        "parameters": {
            "type": "object",
            "properties": {
                "task_id": {"type": "integer", "description": "ID of the task to update"},
                "description": {"type": "string", "description": "New task description"}
            },
            "required": ["task_id", "description"]
        }
    },
    {
        "name": "todo_start",
        "description": "Mark a task as in progress (shows ▶ indicator)",
        "parameters": {
            "type": "object",
            "properties": {"task_id": {"type": "integer", "description": "ID of the task to start"}},
            "required": ["task_id"]
        }
    },
    {
        "name": "todo_done",
        "description": "Mark a task as complete after finishing it",
        "parameters": {
            "type": "object",
            "properties": {"task_id": {"type": "integer", "description": "ID of the task to mark done"}},
            "required": ["task_id"]
        }
    },
    {
        "name": "todo_skip",
        "description": "Skip a task that's not needed or blocked, with optional reason",
        "parameters": {
            "type": "object",
            "properties": {
                "task_id": {"type": "integer", "description": "ID of the task to skip"},
                "reason": {"type": "string", "description": "Optional reason for skipping"}
            },
            "required": ["task_id"]
        }
    },
    {
        "name": "todo_clear",
        "description": "Clear all tasks to start a fresh to-do list for a new workflow",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "todo_list",
        "description": "Show current to-do list status",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "task_complete",
        "description": "Call this when you have finished ALL requested tasks. This signals completion.",
        "parameters": {
            "type": "object",
            "properties": {"summary": {"type": "string", "description": "Brief summary of what was accomplished"}},
            "required": ["summary"]
        }
    }
]

# System prompt that enforces agentic behavior
SYSTEM_PROMPT = """You are Tinker, an expert AI coding assistant. You have access to tools and MUST use them to complete tasks.

## CRITICAL RULES

### 1. DYNAMIC TASK TRACKING
Create and manage your to-do list dynamically:
- **At start**: todo_add(tasks=[...]) to plan initial steps
- **Mid-task**: todo_add(tasks=[...], after_id=N) when you discover new work needed
- **Track progress**: todo_start(task_id=N) → work → todo_done(task_id=N)
- **Adapt**: todo_update() to modify tasks, todo_skip(reason=...) if not needed
- **New workflow**: todo_clear() then todo_add() for completely new tasks
- **Finish**: task_complete(summary="...") when ALL done

### 2. AGENTIC DEBUG/TEST LOOP
When debugging, testing, or running code, work autonomously until success:
1. **Execute**: Run the command/test with execute_command
2. **Analyze**: Read the output carefully for errors
3. **Fix**: If errors found, read the relevant file(s), write fixes
4. **Retry**: Run again, repeat until success or identify blocking issue
5. **Add tasks**: If you discover additional work, use todo_add(after_id=current_task)

Example debug loop:
```
todo_add(tasks=["Run tests", "Fix any failures", "Verify all pass"])
todo_start(task_id=1)
execute_command(command="npm test")
# If tests fail: read failing file, write fix, run again
# If new issue discovered: todo_add(tasks=["Fix X"], after_id=1)
# Keep iterating until tests pass
todo_done(task_id=1)
```

### 3. FILE DISCIPLINE
- Create EXACTLY the files requested - no more, no less
- For small files (<10K chars): Write complete content in one write_file call
- For large files (>10K chars): Use chunked writes:
  1. First chunk: write_file(path="file.py", content="...", finalize=false)
  2. Middle chunks: write_file(path="file.py", content="...", finalize=false)
  3. Last chunk: write_file(path="file.py", content="...", finalize=true)

### 3.1. READING FILES
- **peek_file**: Use for browsing/exploring files to understand structure. Returns summary with first/last lines.
- **read_file**: Use when you need to EDIT a file. Always returns FULL content (no truncation).
  - Before editing: read_file(path="file.py") to get complete content
  - For context/browsing: peek_file(path="file.py") to see structure

### 4. COMMAND EXECUTION
- Safe commands (ls, cat, tests, builds) run automatically
- Elevated commands (rm -rf, etc.) prompt for approval
- Package installs run interactively for password entry
- Always check command output for errors before proceeding

### 5. AUTONOMOUS PROBLEM SOLVING
When given a task like "fix this bug" or "make tests pass":
1. Don't stop at first attempt - iterate until success
2. Read error messages carefully
3. Search codebase if needed (search_code)
4. Make incremental fixes and re-test
5. Add discovered subtasks to your to-do list
6. Only call task_complete when truly finished

### 6. RESPONSE FORMAT
- Call tools IMMEDIATELY - don't explain first
- Chain tools efficiently
- Be concise when responding to user

Available tools: read_file, peek_file, write_file, list_files, search_code, execute_command, run_tests, web_search, todo_add, todo_update, todo_start, todo_done, todo_skip, todo_clear, todo_list, task_complete"""

class GeminiClient:
    """Gemini API client with proper function calling support"""
    
    def __init__(self, config: Config):
        self.config = config
        self.model = config.get("model")
        self.api_key = config.get("gemini_api_key", "")
        self.base_url = "https://generativelanguage.googleapis.com/v1beta"
    
    def _get_model_config(self) -> Dict:
        for m in GEMINI_MODELS:
            if m["id"] == self.model:
                return m
        return {"use_streaming": True}
    
    def generate(self, contents: List[Dict], use_streaming: bool = None) -> Dict:
        """Make a single API call and return the full response"""
        try:
            import requests
        except ImportError:
            return {"error": "Install requests: pip install requests"}
        
        if not self.api_key:
            return {"error": "No API key set. Run: tinker key"}
        
        model_config = self._get_model_config()
        if use_streaming is None:
            use_streaming = model_config.get("use_streaming", True)
        
        generation_config = {
            "temperature": self.config.get("temperature", 0.7),
            "maxOutputTokens": self.config.get("max_output_tokens", 65536),
            "topP": 0.95,
        }
        
        # Add thinking configuration for Gemini 3 models
        if "gemini-3" in self.model:
            generation_config["thinkingConfig"] = {
                "thinkingBudget": 8192  # Allow model to think before responding
            }
        
        request_body = {
            "contents": contents,
            "generationConfig": generation_config,
            "tools": [{"functionDeclarations": FUNCTION_DECLARATIONS}],
            "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
            "toolConfig": {
                "functionCallingConfig": {
                    "mode": "AUTO"  # Let Gemini decide when to call functions
                }
            }
        }
        
        # Use non-streaming endpoint for more reliable function calling
        endpoint = "generateContent" if not use_streaming else "streamGenerateContent"
        url = f"{self.base_url}/models/{self.model}:{endpoint}?key={self.api_key}"
        
        debug_log(f"API call to {self.model} (streaming={use_streaming})")
        debug_log(f"Contents length: {len(contents)}")
        
        try:
            if use_streaming:
                return self._streaming_request(url, request_body)
            else:
                r = requests.post(url, json=request_body, timeout=180)
                r.raise_for_status()
                return r.json()
        
        except requests.exceptions.HTTPError as e:
            error_body = ""
            error_code = None
            try:
                error_body = e.response.text[:1000]
                # Try to parse error details
                try:
                    error_json = e.response.json()
                    if "error" in error_json:
                        error_code = error_json["error"].get("code")
                        error_message = error_json["error"].get("message", "")
                        error_body = error_message
                except:
                    pass
            except:
                pass
            
            if e.response.status_code == 429:
                return {"error": "RATE_LIMIT", "message": f"Rate limit exceeded. Free tier: 2-15 RPM. Wait 60s.\n{error_body}"}
            elif e.response.status_code == 400:
                # Check for token/context limit errors
                error_lower = error_body.lower()
                if any(phrase in error_lower for phrase in [
                    "context length", "token limit", "maximum context", "RESOURCE_EXHAUSTED",
                    "input too long", "context window", "exceeded", "too many requests",
                    "rate limit exceeded", "quota exceeded", "resource exhausted",
                    "service unavailable", "temporarily unavailable", "try again later",
                    "please try again later", "please try again",
                ]):
                    return {"error": "CONTEXT_LIMIT", "message": f"Context limit reached: {error_body}"}
                return {"error": "BAD_REQUEST", "message": f"Bad request: {error_body}"}
            else:
                return {"error": f"API_ERROR_{e.response.status_code}", "message": f"API error {e.response.status_code}: {error_body}"}
        
        except requests.exceptions.Timeout:
            return {"error": "TIMEOUT", "message": "Request timed out (180s). Continuing with new session..."}
        
        except Exception as e:
            return {"error": "REQUEST_FAILED", "message": f"Request failed: {e}"}
    
    def _streaming_request(self, url: str, request_body: Dict) -> Dict:
        """Handle streaming request and return complete response"""
        import requests
        
        try:
            r = requests.post(url, json=request_body, stream=True, timeout=180)
            r.raise_for_status()
        except requests.exceptions.HTTPError as e:
            error_body = ""
            try:
                error_body = e.response.text[:1000]
                try:
                    error_json = e.response.json()
                    if "error" in error_json:
                        error_message = error_json["error"].get("message", "")
                        error_body = error_message
                except:
                    pass
            except:
                pass
            
            if e.response.status_code == 429:
                return {"error": "RATE_LIMIT", "message": f"Rate limit exceeded: {error_body}"}
            elif e.response.status_code == 400:
                error_lower = error_body.lower()
                if any(phrase in error_lower for phrase in [
                    "context length", "token limit", "maximum context",
                    "input too long", "context window", "exceeded", "RESOURCE_EXHAUSTED",
                    "too many requests", "rate limit exceeded", "quota exceeded",
                    "resource exhausted", "service unavailable", "temporarily unavailable",
                    "try again later", "please try again later", "please try again",
                ]):
                    return {"error": "CONTEXT_LIMIT", "message": f"Context limit reached: {error_body}"}
                return {"error": "BAD_REQUEST", "message": f"Bad request: {error_body}"}
            else:
                return {"error": f"API_ERROR_{e.response.status_code}", "message": f"API error {e.response.status_code}: {error_body}"}
        except requests.exceptions.Timeout:
            return {"error": "TIMEOUT", "message": "Request timed out (180s). Continuing with new session..."}
        except Exception as e:
            return {"error": "REQUEST_FAILED", "message": f"Request failed: {e}"}
        
        # Collect all chunks (only reached if no exception)
        full_text = ""
        fc_parts = []  # Keep full parts to preserve thought_signature
        finish_reason = None
        
        buffer = ""
        for chunk in r.iter_content(chunk_size=None):
            if not chunk:
                continue
            
            buffer += chunk.decode('utf-8', errors='ignore')
            
            # Try to parse JSON array or objects
            try:
                # Gemini streaming returns a JSON array
                if buffer.strip().startswith('['):
                    # Try parsing as array
                    data = json.loads(buffer)
                    buffer = ""
                    
                    for item in data:
                        result = self._extract_from_candidate(item)
                        if result.get("text"):
                            full_text += result["text"]
                        if result.get("fc_parts"):
                            fc_parts.extend(result["fc_parts"])
                        if result.get("finish_reason"):
                            finish_reason = result["finish_reason"]
                
            except json.JSONDecodeError:
                # Not complete yet, keep buffering
                pass
        
        # Build response in same format as non-streaming
        # Preserve original parts structure for thought_signature
        parts = []
        if full_text:
            parts.append({"text": full_text})
        parts.extend(fc_parts)  # Use full parts to preserve thought_signature
        
        return {
            "candidates": [{
                "content": {"parts": parts, "role": "model"},
                "finishReason": finish_reason or "STOP"
            }]
        }
    
    def _extract_from_candidate(self, data: Dict) -> Dict:
        """Extract text, function call parts, and finish reason from a candidate"""
        result = {"text": "", "fc_parts": [], "finish_reason": None}
        
        candidates = data.get("candidates", [])
        for candidate in candidates:
            content = candidate.get("content", {})
            parts = content.get("parts", [])
            
            for part in parts:
                if part.get("text"):
                    result["text"] += part["text"]
                if part.get("functionCall"):
                    # Keep full part to preserve thought_signature
                    result["fc_parts"].append(part)
            
            if candidate.get("finishReason"):
                result["finish_reason"] = candidate["finishReason"]
        
        return result

class TinkerSession:
    def __init__(self, config: Config, project_dir: Path, continuation_state: Dict = None):
        self.config = config
        self.project_dir = project_dir
        self.context = SmartContext(project_dir, config)
        self.tools = MCPTools(project_dir, self.context)
        self.client = GeminiClient(config)
        self.contents = []  # Gemini conversation format
        self.max_iterations = config.get("max_iterations", 0)  # 0 = unlimited
        self.original_user_input = continuation_state.get("user_input") if continuation_state else None
        self._init(continuation_state)
    
    def _init(self, continuation_state: Dict = None):
        if continuation_state:
            # Continuation session - use compressed context and continuation prompt
            print(f"{Colors.DIM}Continuing session...{Colors.RESET}", end='', flush=True)
            ctx = self.context.build_context(self.config.get("token_budget", 1000000))
            
            # Restore to-do list if present
            if continuation_state.get("todo_list"):
                for task in continuation_state["todo_list"]:
                    self.tools.todo.tasks.append(task)
                    if task["id"] >= self.tools.todo.next_id:
                        self.tools.todo.next_id = task["id"] + 1
            
            # Create continuation prompt
            todo_summary = self.tools.todo.format_list() if self.tools.todo.tasks else "No tasks yet"
            files_created = continuation_state.get("files_created", [])
            recent_summary = continuation_state.get("recent_summary", "Working on task...")
            
            continuation_prompt = f"""CONTINUATION SESSION - Previous session hit context limit or timeout.

Original task: {continuation_state.get('user_input', 'Unknown')}

Current status:
{todo_summary}

Files created so far: {len(files_created)}
{chr(10).join(f'  • {f}' for f in files_created[:10])}
{'  ... and more' if len(files_created) > 10 else ''}

Recent progress: {recent_summary}

Project context (compressed):
{ctx[:5000]}

IMPORTANT: Continue from where you left off. Check the to-do list, verify files created, and continue working until task_complete is called. Do NOT restart the task."""
            
            self.contents.append({
                "role": "user",
                "parts": [{"text": continuation_prompt}]
            })
            self.contents.append({
                "role": "model",
                "parts": [{"text": "I'll continue from where we left off. Let me check the current state and proceed."}]
            })
            print(f"\r{Colors.GREEN}✓ Resumed{Colors.RESET}     ")
        else:
            # New session
            print(f"{Colors.DIM}Building context...{Colors.RESET}", end='', flush=True)
            ctx = self.context.build_context(self.config.get("token_budget", 1000000))
            print(f"\r{Colors.GREEN}✓ Ready{Colors.RESET}     ")
            
            # Initial context as first user message
            self.contents.append({
                "role": "user",
                "parts": [{"text": f"Project context:\n\n{ctx}\n\nReady to assist. What would you like me to do?"}]
            })
            self.contents.append({
                "role": "model", 
                "parts": [{"text": "I've analyzed the project. What would you like me to help with?"}]
            })
    
    def _create_continuation_state(self, user_input: str) -> Dict:
        """Create state snapshot for continuation"""
        # Get recent conversation summary (last 3-5 messages)
        recent_messages = []
        for msg in self.contents[-10:]:
            if msg.get("role") == "model":
                parts = msg.get("parts", [])
                for part in parts:
                    if part.get("text"):
                        recent_messages.append(part["text"][:200])
        
        recent_summary = " | ".join(recent_messages[-3:]) if recent_messages else "Working on task..."
        
        return {
            "user_input": user_input or self.original_user_input,
            "todo_list": self.tools.todo.get_all(),
            "files_created": list(self.tools.files_created),
            "recent_summary": recent_summary
        }
    
    def chat(self, user_input: str, is_continuation: bool = False):
        # Store original input for continuation
        if not is_continuation:
            self.original_user_input = user_input
        
        # Add user message (skip if continuation, already added in _init)
        if not is_continuation:
            self.contents.append({
                "role": "user",
                "parts": [{"text": user_input}]
            })
        
        print(f"\n{Colors.CYAN}Tinker:{Colors.RESET} ", end='', flush=True)
        
        # Agentic loop - keep going until task_complete or max iterations
        iteration = 0
        max_continuations = 10  # Prevent infinite continuation loops
        continuation_count = 0
        
        while self.max_iterations == 0 or iteration < self.max_iterations:
            iteration += 1
            debug_log(f"Iteration {iteration}")
            
            response = self.client.generate(self.contents)
            
            # Check for errors that require continuation
            if "error" in response:
                error_type = response.get("error", "")
                error_msg = response.get("message", response.get("error", ""))
                
                # Handle continuation-eligible errors
                if error_type in ["CONTEXT_LIMIT", "TIMEOUT"]:
                    continuation_count += 1
                    if continuation_count > max_continuations:
                        print(f"\n{Colors.RED}Too many continuations ({max_continuations}). Stopping.{Colors.RESET}")
                        return
                    
                    print(f"\n{Colors.YELLOW}⚠ {error_msg}{Colors.RESET}")
                    print(f"{Colors.DIM}Creating continuation session...{Colors.RESET}")
                    
                    # Create continuation state
                    continuation_state = self._create_continuation_state(user_input)
                    
                    # Create new session with continuation
                    new_session = TinkerSession(self.config, self.project_dir, continuation_state)
                    new_session.original_user_input = user_input
                    
                    # Transfer tools state
                    new_session.tools.files_created = self.tools.files_created.copy()
                    new_session.tools.files_writing = self.tools.files_writing.copy()
                    
                    # Continue in new session
                    new_session.chat(user_input, is_continuation=True)
                    return
                
                # Handle rate limit with retry
                elif error_type == "RATE_LIMIT":
                    print(f"\n{Colors.YELLOW}⚠ {error_msg}{Colors.RESET}")
                    print(f"{Colors.DIM}Waiting 65 seconds for rate limit...{Colors.RESET}")
                    import time
                    time.sleep(65)
                    print(f"{Colors.GREEN}✓ Resuming...{Colors.RESET}")
                    continue  # Retry the same request
                
                # Other errors - show and stop
                else:
                    print(f"\n{Colors.RED}{error_msg}{Colors.RESET}")
                    return
            
            # Extract response content
            candidates = response.get("candidates", [])
            if not candidates:
                print(f"\n{Colors.YELLOW}No response from model{Colors.RESET}")
                return
            
            candidate = candidates[0]
            content = candidate.get("content", {})
            parts = content.get("parts", [])
            finish_reason = candidate.get("finishReason", "")
            
            # Process parts - preserve original parts for thought signatures (Gemini 3)
            text_parts = []
            function_calls = []
            original_fc_parts = []  # Preserve original parts with thought_signature
            
            for part in parts:
                if part.get("text"):
                    text_parts.append(part["text"])
                if part.get("functionCall"):
                    function_calls.append(part["functionCall"])
                    original_fc_parts.append(part)  # Keep full part including thought_signature
            
            # Print any text
            if text_parts:
                full_text = "".join(text_parts)
                print(full_text, end='', flush=True)
                
                # Only add text to conversation if no function calls
                # Otherwise we'll add everything together below
                if not function_calls:
                    self.contents.append({
                        "role": "model",
                        "parts": [{"text": full_text}]
                    })
            
            # If no function calls, we're done
            if not function_calls:
                print()
                return
            
            # Execute function calls
            function_responses = []
            task_completed = False
            
            for fc in function_calls:
                name = fc.get("name")
                args = fc.get("args", {})
                
                debug_log(f"Function call: {name}({json.dumps(args)[:100]})")
                
                # Display function call
                if name == "write_file":
                    path = args.get("path", "unknown")
                    finalize = args.get("finalize", True)
                    mode = args.get("mode", "overwrite")
                    chunk_info = ""
                    if not finalize:
                        chunk_info = " [chunk]"
                    elif mode == "append":
                        chunk_info = " [append]"
                    print(f"\n{Colors.MAGENTA}[write_file]{Colors.RESET} {Colors.CYAN}{path}{chunk_info}{Colors.RESET} ", end='', flush=True)
                elif name == "read_file":
                    path = args.get("path", "unknown")
                    print(f"\n{Colors.MAGENTA}[read_file]{Colors.RESET} {Colors.CYAN}{path}{Colors.RESET} ", end='', flush=True)
                elif name == "peek_file":
                    path = args.get("path", "unknown")
                    print(f"\n{Colors.CYAN}[peek_file]{Colors.RESET} {Colors.DIM}{path}{Colors.RESET} ", end='', flush=True)
                elif name == "execute_command":
                    cmd = args.get("command", "unknown")
                    print(f"\n{Colors.MAGENTA}[execute]{Colors.RESET} {Colors.DIM}{cmd[:60]}{Colors.RESET} ", end='', flush=True)
                elif name == "run_tests":
                    fw = args.get("framework", "auto")
                    print(f"\n{Colors.MAGENTA}[run_tests]{Colors.RESET} {Colors.DIM}{fw}{Colors.RESET} ", end='', flush=True)
                elif name == "search_code":
                    pattern = args.get("pattern", "?")
                    print(f"\n{Colors.MAGENTA}[search_code]{Colors.RESET} {Colors.DIM}{pattern[:40]}{Colors.RESET} ", end='', flush=True)
                elif name == "web_search":
                    query = args.get("query", "?")
                    print(f"\n{Colors.CYAN}[web_search]{Colors.RESET} {Colors.DIM}{query[:50]}{Colors.RESET} ", end='', flush=True)
                # Todo tools with distinct colors
                elif name == "todo_add":
                    tasks = args.get("tasks", [])
                    after_id = args.get("after_id")
                    after_text = f" after #{after_id}" if after_id else ""
                    print(f"\n{Colors.BLUE}[todo_add]{Colors.RESET} {len(tasks)} task(s){after_text} ", end='', flush=True)
                elif name == "todo_update":
                    task_id = args.get("task_id", "?")
                    print(f"\n{Colors.BLUE}[todo_update]{Colors.RESET} #{task_id} ", end='', flush=True)
                elif name == "todo_start":
                    task_id = args.get("task_id", "?")
                    print(f"\n{Colors.BLUE}[todo_start]{Colors.RESET} #{task_id} ", end='', flush=True)
                elif name == "todo_done":
                    task_id = args.get("task_id", "?")
                    print(f"\n{Colors.BLUE}[todo_done]{Colors.RESET} #{task_id} ", end='', flush=True)
                elif name == "todo_skip":
                    task_id = args.get("task_id", "?")
                    reason = args.get("reason", "")
                    reason_text = f" ({reason[:20]})" if reason else ""
                    print(f"\n{Colors.BLUE}[todo_skip]{Colors.RESET} #{task_id}{reason_text} ", end='', flush=True)
                elif name == "todo_clear":
                    print(f"\n{Colors.BLUE}[todo_clear]{Colors.RESET} ", end='', flush=True)
                elif name == "todo_list":
                    print(f"\n{Colors.BLUE}[todo_list]{Colors.RESET} ", end='', flush=True)
                elif name == "task_complete":
                    pass  # Handle below
                else:
                    print(f"\n{Colors.MAGENTA}[{name}]{Colors.RESET} ", end='', flush=True)
                
                # Execute tool
                result = self.tools.execute(name, args, self.config.get("auto_approve", False))
                
                # Show result status
                if name == "task_complete":
                    task_completed = True
                    summary = args.get("summary", "Task completed")
                    print(f"\n{Colors.GREEN}{'━' * 50}{Colors.RESET}")
                    print(f"{Colors.GREEN}{Colors.BOLD}✓ Task Complete{Colors.RESET}")
                    print(f"{Colors.GREEN}{'━' * 50}{Colors.RESET}")
                    print(f"\n{summary}")
                    if self.tools.files_created:
                        print(f"\n{Colors.CYAN}Files created:{Colors.RESET}")
                        for f in sorted(self.tools.files_created):
                            print(f"  • {f}")
                    print(f"\n{Colors.GREEN}{'━' * 50}{Colors.RESET}\n")
                elif "✓" in result or not result.strip().startswith("Error:"):
                    print(f"{Colors.GREEN}✓{Colors.RESET}")
                else:
                    print(f"{Colors.RED}✗{Colors.RESET}")
                    if result.strip().startswith("Error:"):
                        print(f"  {Colors.DIM}{result[:100]}{Colors.RESET}")
                
                function_responses.append({
                    "name": name,
                    "response": {"result": result}
                })
            
            if task_completed:
                return
            
            # Add function call and response to conversation
            # Use original parts to preserve thought_signature for Gemini 3 models
            model_parts = []
            if text_parts:
                model_parts.append({"text": "".join(text_parts)})
            # Add original function call parts (includes thought_signature if present)
            model_parts.extend(original_fc_parts)
            
            self.contents.append({
                "role": "model",
                "parts": model_parts
            })
            
            # Then add function responses
            self.contents.append({
                "role": "user",
                "parts": [{"functionResponse": fr} for fr in function_responses]
            })
            
            print(f"{Colors.CYAN}Tinker:{Colors.RESET} ", end='', flush=True)
        
        if self.max_iterations > 0:
            print(f"\n{Colors.YELLOW}Max iterations reached ({self.max_iterations}){Colors.RESET}")

def set_api_key():
    cfg = Config()
    print(f"\n{Colors.BOLD}Gemini API Key{Colors.RESET}\n")
    print(f"Get free key: {Colors.CYAN}https://aistudio.google.com/apikey{Colors.RESET}\n")
    
    try:
        key = getpass.getpass("Enter key (hidden): ")
        if key.strip():
            cfg.set("gemini_api_key", key.strip())
            print(f"\n{Colors.GREEN}✓{Colors.RESET} Gemini key saved")
        else:
            print(f"\n{Colors.YELLOW}Cancelled{Colors.RESET}")
    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Cancelled{Colors.RESET}")

def show_models():
    print(f"\n{Colors.BOLD}Gemini Models{Colors.RESET}\n")
    for m in GEMINI_MODELS:
        streaming = "streaming" if m.get("use_streaming") else "non-streaming"
        print(f"{Colors.CYAN}#{m['rank']}{Colors.RESET} {Colors.BOLD}{m['name']}{Colors.RESET}")
        print(f"    ID: {m['id']} ({streaming})")
        print(f"    {m['desc']}")
        print(f"    Limits: {m['limits']}\n")
    print(f"{Colors.CYAN}Switch:{Colors.RESET} tinker switch <model-id>\n")

def switch_model(model_id: str = None):
    cfg = Config()
    
    if model_id:
        valid_ids = [m['id'] for m in GEMINI_MODELS]
        if model_id not in valid_ids:
            print(f"{Colors.RED}Invalid model: {model_id}{Colors.RESET}")
            print(f"{Colors.YELLOW}Valid:{Colors.RESET} {', '.join(valid_ids)}")
            return False
        
        cfg.set('model', model_id)
        model_name = next((m['name'] for m in GEMINI_MODELS if m['id'] == model_id), model_id)
        print(f"{Colors.GREEN}✓{Colors.RESET} Switched to {Colors.CYAN}{model_name}{Colors.RESET}")
        return True
    else:
        # Interactive selection
        import sys
        import termios
        import tty
        
        current = cfg.get('model')
        selected = next((i for i, m in enumerate(GEMINI_MODELS) if m['id'] == current), 0)
        
        def get_key():
            fd = sys.stdin.fileno()
            old = termios.tcgetattr(fd)
            try:
                tty.setraw(fd)
                ch = sys.stdin.read(1)
                if ch == '\x1b':
                    ch += sys.stdin.read(2)
                return ch
            finally:
                termios.tcsetattr(fd, termios.TCSADRAIN, old)
        
        def display(sel):
            print("\033[2J\033[H")
            print(f"{Colors.BOLD}Select Model (↑/↓, Enter to confirm):{Colors.RESET}\n")
            for i, m in enumerate(GEMINI_MODELS):
                curr = " ← current" if m['id'] == current else ""
                if i == sel:
                    print(f"{Colors.GREEN}▶ {Colors.BOLD}{m['name']}{curr}{Colors.RESET}")
                    print(f"  {Colors.GREEN}{m['desc']}{Colors.RESET}")
                else:
                    print(f"  {m['name']}{curr}")
                    print(f"  {Colors.DIM}{m['desc']}{Colors.RESET}")
                print()
        
        try:
            while True:
                display(selected)
                key = get_key()
                
                if key == '\x1b[A': selected = (selected - 1) % len(GEMINI_MODELS)
                elif key == '\x1b[B': selected = (selected + 1) % len(GEMINI_MODELS)
                elif key in ['\r', '\n']:
                    model = GEMINI_MODELS[selected]
                    cfg.set('model', model['id'])
                    print(f"\n{Colors.GREEN}✓{Colors.RESET} Switched to {Colors.CYAN}{model['name']}{Colors.RESET}")
                    return True
                elif key == '\x03':
                    print(f"\n{Colors.YELLOW}Cancelled{Colors.RESET}")
                    return False
        except:
            print(f"\n{Colors.YELLOW}Cancelled{Colors.RESET}")
            return False

def show_config():
    cfg = Config()
    print(f"\n{Colors.BOLD}Configuration{Colors.RESET}\n")
    print(f"  {Colors.CYAN}model{Colors.RESET}: {cfg.get('model')}")
    print(f"  {Colors.CYAN}context_compression{Colors.RESET}: {cfg.get('context_compression', 'smart')}")
    print(f"  {Colors.CYAN}auto_approve{Colors.RESET}: {cfg.get('auto_approve')}")
    print(f"  {Colors.CYAN}max_output_tokens{Colors.RESET}: {cfg.get('max_output_tokens'):,}")
    has_key = bool(cfg.get("gemini_api_key"))
    status = f"{Colors.GREEN}✓ Set{Colors.RESET}" if has_key else f"{Colors.RED}✗ Not set{Colors.RESET}"
    print(f"  {Colors.CYAN}gemini_api_key{Colors.RESET}: {status}")
    print()
    print(f"  {Colors.DIM}Compression modes:{Colors.RESET}")
    print(f"    {Colors.DIM}smart   - Signatures + structure (5-10x smaller) [recommended]{Colors.RESET}")
    print(f"    {Colors.DIM}minimal - Structure only (smallest, uses read_file){Colors.RESET}")
    print(f"    {Colors.DIM}full    - Full file contents (original behavior){Colors.RESET}")
    print()

def main():
    parser = argparse.ArgumentParser(description=f"Tinker {VERSION}")
    parser.add_argument('command', nargs='?', default='chat')
    parser.add_argument('args', nargs='*')
    parser.add_argument('--version', action='version', version=f'Tinker {VERSION}')
    parser.add_argument('--debug', action='store_true', help='Enable debug output')
    
    args = parser.parse_args()
    
    if args.debug:
        os.environ["TINKER_DEBUG"] = "1"
    
    if args.command == 'models':
        show_models()
        return
    
    if args.command == 'key':
        set_api_key()
        return
    
    if args.command == 'config':
        show_config()
        return
    
    if args.command == 'switch':
        model_id = args.args[0] if args.args else None
        switch_model(model_id)
        return
    
    cfg = Config()
    proj = Path.cwd()
    
    has_key = bool(cfg.get("gemini_api_key"))
    
    print(f"\n{Colors.BOLD}Tinker {VERSION}{Colors.RESET}")
    print(f"Model: {Colors.CYAN}{cfg.get('model')}{Colors.RESET}")
    print(f"Project: {Colors.CYAN}{proj.name}{Colors.RESET}")
    print(f"Context: {Colors.CYAN}{cfg.get('context_compression', 'smart')}{Colors.RESET} compression")
    
    if not has_key:
        print(f"\n{Colors.RED}⚠ No API key{Colors.RESET}")
        print(f"Run: {Colors.CYAN}tinker key{Colors.RESET}")
        print(f"Get free: {Colors.CYAN}https://aistudio.google.com/apikey{Colors.RESET}")
        return
    
    print(f"\nType {Colors.YELLOW}'exit'{Colors.RESET} or {Colors.YELLOW}'help'{Colors.RESET}")
    if HAS_PROMPT_TOOLKIT:
        print(f"{Colors.DIM}Enhanced input: Ctrl+Left/Right (word nav), Ctrl+R (search history){Colors.RESET}")
    print()
    
    session = TinkerSession(cfg, proj)
    enhanced_input = EnhancedInput()
    
    try:
        while True:
            try:
                inp = enhanced_input.get_input("You: ")
                if not inp: continue
                
                if inp.lower() in ['exit', 'quit', 'q']:
                    print(f"\n{Colors.CYAN}Goodbye!{Colors.RESET}")
                    break
                
                if inp.lower() == 'help':
                    print(f"""
{Colors.BOLD}Commands:{Colors.RESET}
  help        - Show this help
  shortcuts   - Show keyboard shortcuts
  exit        - Exit Tinker
  clear       - Clear conversation
  models      - Show available models
  switch      - Change model
  key         - Set API key
  config      - Show configuration
  auto on     - Enable auto-approve
  auto off    - Disable auto-approve

{Colors.BOLD}Context Compression:{Colors.RESET}
  compress smart   - Signatures + structure (5-10x smaller) [default]
  compress minimal - Structure only (smallest)
  compress full    - Full file contents (original)
                    """)
                    continue
                
                if inp.lower() == 'shortcuts':
                    EnhancedInput.print_shortcuts()
                    continue
                
                if inp.lower() in ['models']:
                    show_models()
                    continue
                
                if inp.lower() in ['switch', 'model']:
                    if switch_model():
                        session.client.model = cfg.get('model')
                    continue
                
                if inp.lower() == 'clear':
                    session = TinkerSession(cfg, proj)
                    print(f"{Colors.GREEN}✓ Cleared{Colors.RESET}")
                    continue
                
                if inp.lower() == 'auto on':
                    cfg.set('auto_approve', True)
                    print(f"{Colors.YELLOW}Auto-approve enabled{Colors.RESET}")
                    continue
                
                if inp.lower() == 'auto off':
                    cfg.set('auto_approve', False)
                    print(f"{Colors.GREEN}Auto-approve disabled{Colors.RESET}")
                    continue
                
                if inp.lower().startswith('compress '):
                    mode = inp.lower().split(' ', 1)[1].strip()
                    if mode in ['smart', 'minimal', 'full']:
                        cfg.set('context_compression', mode)
                        print(f"{Colors.GREEN}✓ Context compression: {mode}{Colors.RESET}")
                        print(f"{Colors.DIM}Use 'clear' to rebuild context with new compression{Colors.RESET}")
                    else:
                        print(f"{Colors.RED}Invalid mode. Use: smart, minimal, full{Colors.RESET}")
                    continue
                
                session.chat(inp)
            
            except KeyboardInterrupt:
                print(f"\n{Colors.CYAN}Goodbye!{Colors.RESET}")
                break
    
    except Exception as e:
        print(f"\n{Colors.RED}Error: {e}{Colors.RESET}")
        if DEBUG:
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    main()
PYTHON_EOF

    # Create config (write via Python so the API key is always valid JSON,
    # even if it contains quotes, backslashes, or other special characters).
    # Note: the venv isn't created yet at this point in the install, so we
    # use the system python3 (already installed by install_deps).
    TINKER_CONFIG_DIR="$CONFIG_DIR" TINKER_GEMINI_KEY="${GEMINI_KEY:-}" python3 -c '
import json, os
from pathlib import Path

config_dir = Path(os.environ["TINKER_CONFIG_DIR"])
config = {
    "model": "gemini-3.8-flash",
    "gemini_api_key": os.environ.get("TINKER_GEMINI_KEY", ""),
    "max_output_tokens": 65536,
    "temperature": 0.7,
    "stream": True,
    "auto_approve": False,
    "max_context_files": 100,
    "token_budget": 1000000,
    "thinking_enabled": True,
}
with open(config_dir / "config.json", "w") as f:
    json.dump(config, f, indent=2)
'
    
    chmod +x "$INSTALL_DIR/tinker.py"
    success "Tinker v7.5 generated"
}

create_wrapper() {
    cat > "$BIN_DIR/tinker" << 'EOF'
#!/usr/bin/env bash
exec "$HOME/.tinker/venv/bin/python3" "$HOME/.tinker/tinker.py" "$@"
EOF
    chmod +x "$BIN_DIR/tinker"
}

install_python() {
    step "Setting Up Python"
    python3 -m venv "$INSTALL_DIR/venv" 2>&1 | grep -v "already" || true
    "$INSTALL_DIR/venv/bin/pip" install --upgrade pip -q
    "$INSTALL_DIR/venv/bin/pip" install requests prompt_toolkit -q
    success "Python ready (with enhanced input)"
}

update_shell() {
    step "Updating Shell"
    
    case "$SHELL_NAME" in
        bash) RC="$HOME/.bashrc" ;;
        zsh) RC="$HOME/.zshrc" ;;
        fish) RC="$HOME/.config/fish/config.fish"; mkdir -p "$(dirname "$RC")" ;;
        *) RC="$HOME/.profile" ;;
    esac
    
    if ! grep -q "/.local/bin" "$RC" 2>/dev/null; then
        if [[ "$SHELL_NAME" == "fish" ]]; then
            echo -e "\n# Tinker\nset -gx PATH \$HOME/.local/bin \$PATH" >> "$RC"
        else
            echo -e "\n# Tinker\nexport PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$RC"
        fi
        success "Shell updated"
    fi
}

show_completion() {
    cat << EOF

╔═══════════════════════════════════════════════════════════╗
║        Tinker v7.5 - Enhanced Agentic Edition             ║
╚═══════════════════════════════════════════════════════════╝

✨ What's New in v7.5:
  • Enhanced input with readline shortcuts:
    - Ctrl+Left/Right: Move by word
    - Ctrl+W/Backspace: Delete word backward
    - Ctrl+R: Reverse search history
    - Up/Down: History navigation
  • Dynamic to-do list (add/update/skip tasks mid-workflow)
  • Agentic debug loop (auto-fix code until tests pass)
  • Smart context compression (5-10x token reduction)
  • Updated to Gemini 3 family: 3.8 Flash (default), 3.1 Pro,
    3.6 Flash, 3.1 Flash-Lite

🚀 Get Started:
  1. exec \$SHELL
  2. cd your-project
  3. tinker

⌨️  Keyboard shortcuts:
  Type 'shortcuts' in Tinker for full list

🔧 Commands:
  tinker        - Start session
  tinker key    - Set Gemini API key
  tinker models - Show available models
  tinker switch - Change models
  tinker config - Show configuration

📖 Get Free API Key:
  https://aistudio.google.com/apikey

🐛 Debug mode:
  TINKER_DEBUG=1 tinker

EOF
}

main() {
    clear
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║         Tinker v7.5 - Enhanced Agentic Edition            ║
║   Enhanced Input | Agentic Debug | Context Compression    ║
╚═══════════════════════════════════════════════════════════╝

EOF
    
    detect_system
    install_deps
    create_dirs
    setup_gemini_key
    generate_tinker
    create_wrapper
    install_python
    update_shell
    show_completion
}

main "$@"
