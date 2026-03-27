#!/usr/bin/env bash
# Usage: bt-agent-respond.sh <MAC> <accept|reject>
MAC="$1"; ACTION="$2"
[ -z "$MAC" ] || [ -z "$ACTION" ] && exit 1
echo "${MAC}|${ACTION}" | socat - UNIX-CONNECT:/tmp/qs_bt_agent.sock 2>/dev/null || printf '%s' "${MAC}|${ACTION}" > /tmp/qs_bt_agent_response 2>/dev/null
