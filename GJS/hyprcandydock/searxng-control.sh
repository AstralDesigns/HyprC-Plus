#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-status}"

case "$ACTION" in
    status)
        if docker ps -q --filter name=hyprcandy-searxng 2>/dev/null | grep -q .; then
            echo "running"
            exit 0
        else
            echo "stopped"
            exit 1
        fi
        ;;
    start)
        # 1. Check if docker daemon is accessible
        if ! docker info >/dev/null 2>&1; then
            if ! systemctl is-active docker >/dev/null 2>&1; then
                sudo -n systemctl start docker 2>/dev/null || sudo systemctl start docker 2>/dev/null || pkexec sh -c "systemctl start docker && chmod 666 /var/run/docker.sock 2>/dev/null || true" || exit 1
            fi
            if ! docker info >/dev/null 2>&1; then
                sudo -n chmod 666 /var/run/docker.sock 2>/dev/null || sudo chmod 666 /var/run/docker.sock 2>/dev/null || pkexec chmod 666 /var/run/docker.sock 2>/dev/null || true
            fi
        fi

        # 2. Check if container is already running
        if docker ps -q --filter name=hyprcandy-searxng 2>/dev/null | grep -q .; then
            echo "already_running"
            exit 0
        fi

        # 3. If container exists but stopped, start it
        if docker ps -a -q --filter name=hyprcandy-searxng 2>/dev/null | grep -q .; then
            docker start hyprcandy-searxng
            exit 0
        fi

        # 4. Create and start container (fallback to docker run if docker compose plugin not installed)
        if docker compose version >/dev/null 2>&1; then
            docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
        elif command -v docker-compose >/dev/null 2>&1; then
            docker-compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
        else
            docker run -d \
                --name hyprcandy-searxng \
                -p 127.0.0.1:8080:8080 \
                -v "$SCRIPT_DIR/searxng-settings:/etc/searxng:rw" \
                -e SEARXNG_SECRET_KEY=hyprcandy-permanent-local-secret-key-3f98a21b44c8 \
                --restart unless-stopped \
                searxng/searxng:latest
        fi
        ;;
    stop)
        docker stop hyprcandy-searxng 2>/dev/null || true
        ;;
esac
