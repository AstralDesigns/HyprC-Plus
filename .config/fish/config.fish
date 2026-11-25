# HyprCandy Fish Configuration

# Set environment variables
set -gx HYPRLAND_LOG_WS 1
set -x EDITOR micro
set -x BROWSER firefox
set -x TERMINAL kitty

# Add local bin to PATH
if test -d ~/.local/bin
    set -x PATH ~/.local/bin $PATH
end

# HyprCandy: cargo bin on PATH
if test -d ~/.cargo/bin
    set -x PATH ~/.cargo/bin $PATH
end

# Aliases
#alias hyprcandy="cd .hyprcandy && git pull && stow --ignore='Candy' --ignore='Candy-Images' --ignore='Dock-SVGs' --ignore='Gifs' --ignore='Logo' --ignore='transparent.png' --ignore='GJS' --ignore='Candy.desktop' --ignore='HyprCandy.png' --ignore='candy-daemon.js' --ignore='candy-launcher.sh' --ignore='toggle-control-center.sh' --ignore='toggle-media-player.sh' --ignore='toggle-system-monitor.sh' --ignore='toggle-weather-widget.sh' --ignore='toggle-hyprland-settings.sh' --ignore='candy-system-monitor.js' --ignore='resources' --ignore='src' --ignore='meson.build' --ignore='README.md' --ignore='run.log' --ignore='test_layout.js' --ignore='test_media_menu.js' --ignore='toggle.js' --ignore='toggle-main.js' --ignore='~' --ignore='candy-main.js' --ignore='gjs-media-player.desktop' --ignore='gjs-toggle-controls.desktop' --ignore='main.js' --ignore='media-main.js' --ignore='SEEK_FEATURE.md' --ignore='setup-custom-icon.sh' --ignore='weather-main.js' */"
alias ll="ls -alF"
alias la="ls -A"
alias l="ls -CF"
alias ..="cd .."
alias ...="cd ../.."
alias grep="grep --color=auto"
alias fgrep="fgrep --color=auto"
alias egrep="egrep --color=auto"
alias update="sudo pacman -Syu"
alias install="sudo pacman -S"
alias search="pacman -Ss"
alias remove="sudo pacman -R"
alias autoremove="sudo pacman -Rs (pacman -Qtdq)"
alias cls="clear"
alias h="history"
alias j="jobs -l"
alias df="df -h"
alias du="du -h"
alias mkdir="mkdir -pv"
alias wget="wget -c"
alias ff="fastfetch"

# Git aliases
alias g="git clone --depth 1"
alias ga="git add ."
alias gc="git commit -m"
function gp
    # Ensure .config/hypr are gitignored before every push
    if not grep -qF ".config/hypr" .gitignore 2>/dev/null
        echo ".config/hypr/hyprviz.conf" >> .gitignore
	    echo ".config/hypr/monitors.conf" >> .gitignore
        git add .gitignore
        git commit -m "chore: ignore personal config dirs"
    end
    git push
end
alias gl="git pull"
alias gs="git status"
alias gd="git diff"
alias gco="git checkout"
alias gb="git branch"
alias glog="git log --oneline --graph --decorate"

# System information
alias sysinfo="fastfetch"
alias weather="curl wttr.in"

# Fun stuff
alias matrix="cmatrix -a -b -r"
alias pipes="pipes.sh"
alias clock="tty-clock -s -c"
alias sea="asciiquarium"

# Start HyprCandy fastfetch
fastfetch

# Initialize Starship prompt
if type -q starship
    starship init fish | source
end

# Welcome message
function fish_greeting
end


# QODER_DISPATCHER_PATH v1
fish_add_path -p -m $HOME/.qoder/entry
# END QODER_DISPATCHER_PATH v1
