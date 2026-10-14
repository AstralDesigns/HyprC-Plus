#!/usr/bin/env bash
# HyprCandy login-shell switcher.
# Pick fish / zsh / bash, then run the SAME full setup the installer performs:
# dependency handling, plugin ecosystems (fisher / oh-my-zsh / bash-completion)
# and config bootstrap — so switching to a shell for the first time works.
# Designed to run inside a floating-installer kitty window (see ControlCenterPopup.qml).

set -u

BOLD=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'
YELLOW=$'\033[33m'; RED=$'\033[31m'; NC=$'\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${CYAN}•${NC} $*"; }
warn() { echo -e "${YELLOW}ℹ${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

SHELLS=(fish zsh bash)
current_shell="$(basename "${SHELL:-none}")"

# ── Dependency handling (pacman; sudo warms a cached ticket once) ─────────────
have()   { command -v "$1" >/dev/null 2>&1; }
pkgs()   { have pacman || { warn "pacman not found — skipping package install: $*"; return 0; }; \
           local missing=() p
           for p in "$@"; do pacman -Qi "$p" >/dev/null 2>&1 || missing+=("$p"); done
           [ ${#missing[@]} -eq 0 ] && return 0
           info "Installing packages: ${missing[*]}"
           sudo pacman -S --needed --noconfirm "${missing[@]}" || err "package install failed: ${missing[*]}"; }
sudo_warm() { have sudo && sudo -v; }

# ── Shared Starship prompt (single file used by every shell) ──────────────────
# Preserved if already present (that's the HyprCandy design install.sh wrote);
# otherwise a matching default is created so bash/fish/zsh all share it.
ensure_starship_toml() {
    local toml="$HOME/.config/starship.toml"
    [ -f "$toml" ] && return 0
    mkdir -p "$HOME/.config"
    cat > "$toml" <<'EOF'
# Starship Configuration for HyprCandy
format = """
$username\
$hostname\
$time $directory\
$git_branch\
$git_state\
$git_status\
$git_metrics\
$fill\
$nodejs\
$python\
$rust\
$golang\
$php\
$java\
$kotlin\
$haskell\
$swift\
$cmd_duration $jobs\
$line_break\
$character"""

[fill]
symbol = " "

[username]
style_user = "bold cyan"
style_root = "bold red"
show_always = true

[directory]
style = "cyan"
read_only = " 🔒"
truncation_length = 4
truncate_to_repo = false

[git_branch]
truncation_length = 4
style = "cyan"

[nodejs]
style = "bold grey"

[python]
style = "bold yellow"

[rust]
style = "bold red"

[time]
time_format = "%T"
disabled = false
style = "bright-white"

[cmd_duration]
style = "grey"

[jobs]
style = "bold cyan"
EOF
    ok "Created default Starship config (all shells share it)."
}

# ── HyprCandy aliases/functions block (shared shape across shells) ────────────
# Emitted into bash/zsh configs; fish has its own syntax.
posix_aliases() {
cat <<'EOF'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias update='sudo pacman -Syu'
alias install='sudo pacman -S'
alias search='pacman -Ss'
alias remove='sudo pacman -R'
alias c='clear'
alias h='history'
alias j='jobs -l'
alias df='df -h'
alias du='du -h'
alias mkdir='mkdir -pv'
alias wget='wget -c'
alias ff='fastfetch'

alias g='git clone --depth 1'
alias ga='git add .'
alias gc='git commit -m'
alias gl='git pull'
alias gs='git status'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias glog='git log --oneline --graph --decorate'
gp() {
    if ! grep -qF ".config/hypr" .gitignore 2>/dev/null; then
        echo ".config/hypr/hyprviz.conf" >> .gitignore
        echo ".config/hypr/monitors.conf" >> .gitignore
        git add .gitignore
        git commit -m "chore: ignore personal config dirs"
    fi
    git push
}

alias sysinfo='fastfetch'
alias weather='curl wttr.in'
alias matrix='cmatrix -a -b -r'
alias pipes='pipes.sh'
alias clock='tty-clock -s -c'
alias sea='asciiquarium'
EOF
}

# ── Bash: full first-time setup + completion/fzf plugins ──────────────────────
setup_bash() {
    pkgs bash bash-completion starship fzf fastfetch git curl
    local rc="$HOME/.bashrc"
    cat > "$HOME/.bash_profile" <<'EOF'
# HyprCandy Bash Profile
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF
    if ! grep -q 'HyprCandy Bash Configuration' "$rc" 2>/dev/null; then
        info "Writing full Bash config (~/.bashrc)"
        {
            echo '# HyprCandy Bash Configuration'
            echo
            echo 'export HYPRLAND_LOG_WS=1'
            echo 'export EDITOR=micro'
            echo 'export TERMINAL=kitty'
            cat <<'EOF'

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) [ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH" ;;
esac

shopt -s histappend
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups

# Bash completion plugin
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# fzf key-bindings + completion
if command -v fzf > /dev/null 2>&1; then
  source <(fzf --bash 2>/dev/null) || { [ -f "$HOME/.fzf.bash" ] && . "$HOME/.fzf.bash"; }
fi

EOF
            posix_aliases
            cat <<'EOF'
# Start HyprCandy fastfetch
fastfetch

# Initialize Starship prompt
if command -v starship > /dev/null 2>&1; then
    eval "$(starship init bash)"
fi
EOF
        } > "$rc"
        ok "Bash config written (completion + fzf + starship enabled)."
    else
        info "Bash config already present — ensuring Starship init."
        grep -q 'starship init bash' "$rc" || \
            printf '\ncommand -v starship >/dev/null 2>&1 && eval "$(starship init bash)"\n' >> "$rc"
    fi
}

# ── Zsh: oh-my-zsh + autosuggestions/syntax-highlighting plugins ──────────────
setup_zsh() {
    pkgs zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search starship git curl
    local rc="$HOME/.zshrc"

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        info "Installing Oh My Zsh…"
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
            && ok "Oh My Zsh installed." || err "Oh My Zsh install failed."
    else
        ok "Oh My Zsh already installed."
    fi

    # Clone plugin repos into ZSH_CUSTOM so they load via the plugins array.
    local custom="${ZSH:-$HOME/.oh-my-zsh}/custom/plugins"
    mkdir -p "$custom"
    [ -d "$custom/zsh-autosuggestions" ] || { info "Cloning zsh-autosuggestions…"; \
        git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$custom/zsh-autosuggestions" >/dev/null 2>&1; }
    [ -d "$custom/zsh-syntax-highlighting" ] || { info "Cloning zsh-syntax-highlighting…"; \
        git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$custom/zsh-syntax-highlighting" >/dev/null 2>&1; }

    if ! grep -q 'HyprCandy Zsh Configuration' "$rc" 2>/dev/null; then
        info "Writing full Zsh config (~/.zshrc)"
        {
            echo '# HyprCandy Zsh Configuration with Oh My Zsh and Starship'
            cat <<'EOF'

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git z zsh-autosuggestions zsh-syntax-highlighting)

export HYPRLAND_LOG_WS=1
export EDITOR=micro
export BROWSER=firefox
export TERMINAL=kitty

if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

source $ZSH/oh-my-zsh.sh

EOF
            posix_aliases
            cat <<'EOF'
# Start HyprCandy fastfetch
fastfetch

# fzf integration
if command -v fzf > /dev/null 2>&1; then
    eval "$(fzf --zsh)"
fi

# Initialize Starship prompt (last, so it owns the prompt)
if command -v starship > /dev/null 2>&1; then
    eval "$(starship init zsh)"
fi
EOF
        } > "$rc"
        ok "Zsh config written (oh-my-zsh + autosuggestions + syntax-highlighting + starship)."
    else
        info "Zsh config already present — ensuring Starship init."
        grep -q 'starship init zsh' "$rc" || \
            printf '\ncommand -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"\n' >> "$rc"
    fi
}

# ── Fish: fisher + autopair/z/fzf/done plugins ────────────────────────────────
setup_fish() {
    pkgs fish fisher starship fzf ripgrep fd fastfetch git curl
    local rc_dir="$HOME/.config/fish"
    local rc="$rc_dir/config.fish"
    mkdir -p "$rc_dir/functions"

    # Ensure the fisher manager function is available.
    if [ ! -f "$rc_dir/functions/fisher.fish" ]; then
        info "Fetching fisher…"
        curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish \
            -o "$rc_dir/functions/fisher.fish"
    fi

    if have fish; then
        info "Installing Fisher plugins (autopair, z, fzf, done)…"
        fish -c 'fisher install jorgebucaran/fisher >/dev/null 2>&1
                 fisher install jorgebucaran/autopair.fish jethrokuan/z patrickf1/fzf.fish franciscolourenco/done' \
            && ok "Fisher plugins installed." || warn "Fisher plugin install skipped/failed."
    fi

    if ! grep -q 'HyprCandy Fish Configuration' "$rc" 2>/dev/null; then
        info "Writing full Fish config (config.fish)"
        cat > "$rc" <<'EOF'
# HyprCandy Fish Configuration

set -gx HYPRLAND_LOG_WS 1
set -x EDITOR micro
set -x BROWSER firefox
set -x TERMINAL kitty

if test -d ~/.local/bin
    set -x PATH ~/.local/bin $PATH
end

# Aliases
alias ll="ls -alF"
alias la="ls -A"
alias l="ls -CF"
alias ..="cd .."
alias ...="cd ../.."
alias grep="grep --color=auto"
alias update="sudo pacman -Syu"
alias install="sudo pacman -S"
alias search="pacman -Ss"
alias remove="sudo pacman -R"
alias df="df -h"
alias du="du -h"
alias mkdir="mkdir -pv"
alias wget="wget -c"
alias ff="fastfetch"

alias g="git clone --depth 1"
alias ga="git add ."
alias gc="git commit -m"
alias gl="git pull"
alias gs="git status"
alias gd="git diff"
alias gco="git checkout"
alias gb="git branch"
alias glog="git log --oneline --graph --decorate"
function gp
    if not grep -qF ".config/hypr" .gitignore 2>/dev/null
        echo ".config/hypr/hyprviz.conf" >> .gitignore
        echo ".config/hypr/monitors.conf" >> .gitignore
        git add .gitignore
        git commit -m "chore: ignore personal config dirs"
    end
    git push
end

alias sysinfo="fastfetch"
alias weather="curl wttr.in"

# Start HyprCandy fastfetch
fastfetch

# Initialize Starship prompt
if type -q starship
    starship init fish | source
end

function fish_greeting
end
EOF
        ok "Fish config written (fisher plugins + starship)."
    else
        info "Fish config already present — ensuring Starship init."
        grep -q 'starship init fish' "$rc" || \
            printf '\nif type -q starship\n    starship init fish | source\nend\n' >> "$rc"
    fi
}

# ── Interactive picker (fzf when available) ──────────────────────────────────
pick_shell() {
    if have fzf; then
        printf '%s\n' "${SHELLS[@]}" \
            | awk -v c="$current_shell" '{ print ($1==c) ? $1"  (current)" : $1 }' \
            | fzf --reverse --border --height=40% --prompt="Shell > "
    else
        echo -e "${CYAN}Choose your login shell:${NC}"
        local i s mark
        for i in "${!SHELLS[@]}"; do
            s="${SHELLS[$i]}"; mark=""
            [ "$s" = "$current_shell" ] && mark=" ${DIM}(current)${NC}"
            printf '  %d) %s%s\n' "$((i+1))" "${BOLD}${s}${NC}" "${mark}"
        done
        local sel
        read -rp "Enter number: " sel
        if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "${#SHELLS[@]}" ]; then
            err "Invalid choice."; return 1
        fi
        echo "${SHELLS[$((sel-1))]}"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
echo -e "${BOLD}HyprCandy Shell Switcher${NC}  ${DIM}(current: ${current_shell})${NC}"
echo

sudo_warm
ensure_starship_toml

choice="$(pick_shell)"
choice="${choice%% *}"   # strip any trailing "(current)" marker from fzf line
[ -z "$choice" ] && { echo "No shell selected — nothing changed."; exit 0; }

if [ "$choice" = "$current_shell" ]; then
    warn "'$choice' is already your login shell — re-applying its full setup."
fi

case "$choice" in
    bash) setup_bash ;;
    zsh)  setup_zsh  ;;
    fish) setup_fish ;;
    *)    err "Unknown shell '$choice'."; exit 1 ;;
esac

# Resolve the binary (setup_* installs it if it was missing).
target_bin="$(command -v "$choice" || true)"
if [ -z "$target_bin" ]; then
    err "'$choice' still not available after setup. Install it manually: sudo pacman -S $choice"
    exit 1
fi

echo -e "${CYAN}Setting login shell to ${BOLD}${choice}${NC}${CYAN} (${target_bin})…${NC}"
if chsh -s "$target_bin"; then
    ok "Default shell set to ${BOLD}${choice}${NC}."
else
    err "chsh failed. Retry manually: chsh -s ${target_bin}"
    exit 1
fi

# For zsh, start it interactively once so Oh My Zsh runs its first-run /
# self-update during the switch; exiting that shell returns here.
if [ "$choice" = "zsh" ]; then
    echo
    echo -e "${CYAN}Launching ${BOLD}zsh${NC}${CYAN} to trigger the Oh My Zsh update — type ${GREEN}exit${NC}${CYAN} when it finishes to continue.${NC}"
    "$target_bin" -i || true
fi

echo
echo -e "${BOLD}Done.${NC} The change takes effect ${YELLOW}on next login${NC} (log out and back in, or restart Hyprland)."
echo -e "To switch this terminal right now, run:  ${GREEN}exec ${choice} -l${NC}"
echo
echo -e "${DIM}Press Enter to close this window…${NC}"; read -r _
