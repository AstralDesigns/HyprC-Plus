#!/usr/bin/env bash
# Usage: obex-agent-respond.sh <MAC> <accept|reject>
MAC="$1"; ACTION="$2"
[ -z "$MAC" ] || [ -z "$ACTION" ] && exit 1
echo "${MAC}|${ACTION}" | socat - UNIX-CONNECT:/tmp/qs_obex_agent.sock 2>/dev/null
