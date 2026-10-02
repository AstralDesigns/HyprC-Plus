#!/usr/bin/env bash
# ── hyprcandy-docker.sh ────────────────────────────────────────────────────────
# Controls the SearXNG Docker container for the HyprCandy launcher web-search tab.
# Designed to be invoked by GJS via GLib async subprocess and permitted via sudoers.

set -e

# Self-elevation via passwordless sudo if not already root
if [ "$EUID" -ne 0 ] && [ -z "$_HYPRCANDY_DOCKER_NO_SUDO" ]; then
    export _HYPRCANDY_DOCKER_NO_SUDO=1
    if sudo -n "$0" "$@" 2>/dev/null; then
        exit $?
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-status}"
CONTAINER_NAME="hyprcandy-searxng"

# Helper to check if docker daemon is responding
ensure_docker_daemon() {
    if ! systemctl is-active docker >/dev/null 2>&1; then
        systemctl start docker 2>/dev/null || true
    fi

    # Wait briefly for docker socket
    local waited=0
    while [ $waited -lt 10 ]; do
        if docker info >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
        waited=$((waited + 1))
    done

    # If running as root, ensure non-root users in 'docker' group can communicate
    if [ -S /var/run/docker.sock ]; then
        chmod 660 /var/run/docker.sock 2>/dev/null || true
        chgrp docker /var/run/docker.sock 2>/dev/null || true
    fi
}

# Fix overlay-on-overlay issue (e.g. CachyOS / Arch BTRFS snapshot cowspace boot)
ensure_storage_driver_ready() {
    if [ "$EUID" -ne 0 ]; then
        return 0
    fi

    local root_fs
    root_fs=$(df -T / 2>/dev/null | awk 'NR==2 {print $2}')
    local test_failed=0

    # If root is overlayfs, containerd overlayfs snapshotter fails with EINVAL
    if [ "$root_fs" = "overlay" ]; then
        test_failed=1
    elif ! docker run --rm --net=none busybox true >/dev/null 2>&1; then
        # Container mount failed, likely storage driver or snapshotter incompatibility
        test_failed=1
    fi

    if [ "$test_failed" -eq 1 ]; then
        # Use /var/cache which resides on persistent BTRFS mount (@cache) even during snapshot boot
        local restart_needed=0
        mkdir -p /var/cache/docker /var/cache/containerd /etc/docker /etc/containerd

        if [ ! -f /etc/docker/daemon.json ] || ! grep -q "/var/cache/docker" /etc/docker/daemon.json 2>/dev/null; then
            cat > /etc/docker/daemon.json << 'EOF'
{
  "data-root": "/var/cache/docker"
}
EOF
            restart_needed=1
        fi

        if [ ! -f /etc/containerd/config.toml ] || ! grep -q "/var/cache/containerd" /etc/containerd/config.toml 2>/dev/null; then
            cat > /etc/containerd/config.toml << 'EOF'
version = 2
root = "/var/cache/containerd"
state = "/run/containerd"
EOF
            systemctl restart containerd 2>/dev/null || true
            restart_needed=1
        fi

        if [ "$restart_needed" -eq 1 ]; then
            systemctl restart docker 2>/dev/null || true
            sleep 1
        fi
    fi
}

ensure_settings_file() {
    mkdir -p "$SCRIPT_DIR/searxng-settings"
    local settings_file="$SCRIPT_DIR/searxng-settings/settings.yml"
    if [ ! -f "$settings_file" ]; then
        cat > "$settings_file" << 'EOF'
use_default_settings: true

general:
  debug: false
  instance_name: "HyprCandy SearXNG"

server:
  port: 8080
  bind_address: "0.0.0.0"
  secret_key: "hyprcandy-permanent-local-secret-key-3f98a21b44c8"
  limiter: false
  image_proxy: true

search:
  safe_search: 0
  formats:
    - html
    - json
EOF
    fi
    chmod 755 "$SCRIPT_DIR/searxng-settings" 2>/dev/null || true
    chmod 644 "$settings_file" 2>/dev/null || true
}

case "$ACTION" in
    status)
        if docker ps -q --filter name="$CONTAINER_NAME" --filter status=running 2>/dev/null | grep -q .; then
            echo "running"
            exit 0
        else
            echo "stopped"
            exit 1
        fi
        ;;

    start)
        ensure_docker_daemon
        ensure_storage_driver_ready
        ensure_settings_file

        # Check if container is already running
        if docker ps -q --filter name="$CONTAINER_NAME" --filter status=running 2>/dev/null | grep -q .; then
            echo "already_running"
            exit 0
        fi

        # If container exists but stopped, attempt start
        if docker ps -a -q --filter name="$CONTAINER_NAME" 2>/dev/null | grep -q .; then
            if docker start "$CONTAINER_NAME" >/dev/null 2>&1; then
                sleep 0.5
                if docker ps -q --filter name="$CONTAINER_NAME" --filter status=running 2>/dev/null | grep -q .; then
                    echo "running"
                    exit 0
                fi
            fi
            # If docker start failed or exited, purge stale container so docker run can recreate it
            docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        fi

        # Launch fresh SearXNG container
        docker run -d \
            --name "$CONTAINER_NAME" \
            -p 127.0.0.1:8080:8080 \
            -v "$SCRIPT_DIR/searxng-settings:/etc/searxng:rw" \
            -e SEARXNG_SECRET_KEY=hyprcandy-permanent-local-secret-key-3f98a21b44c8 \
            --restart unless-stopped \
            searxng/searxng:latest >/dev/null 2>&1 || true

        # Verify it reaches running status
        for _ in {1..12}; do
            if docker ps -q --filter name="$CONTAINER_NAME" --filter status=running 2>/dev/null | grep -q .; then
                echo "running"
                exit 0
            fi
            sleep 0.5
        done

        echo "failed"
        exit 1
        ;;

    stop)
        docker stop -t 2 "$CONTAINER_NAME" >/dev/null 2>&1 || true
        echo "stopped"
        exit 0
        ;;

    restart)
        "$0" stop
        sleep 1
        "$0" start
        ;;

    setup)
        ensure_docker_daemon
        ensure_storage_driver_ready
        ensure_settings_file
        echo "setup_complete"
        exit 0
        ;;

    *)
        echo "Usage: $0 {status|start|stop|restart|setup}"
        exit 1
        ;;
esac
