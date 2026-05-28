#!/bin/bash
# Health check for hermes services
# Returns JSON status of all services

PID_DIR="/run/hermes"

check_process() {
    local name="$1"
    local pidfile="${PID_DIR}/${name}.pid"

    if [ -f "${pidfile}" ]; then
        local pid
        pid=$(cat "${pidfile}")
        if kill -0 "${pid}" 2>/dev/null; then
            echo "running"
            return 0
        fi
    fi
    echo "stopped"
    return 1
}

AGENT_STATUS=$(check_process "agent")
WEBUI_STATUS=$(check_process "webui")

cat <<EOF
{
  "agent": "${AGENT_STATUS}",
  "webui": "${WEBUI_STATUS}"
}
EOF
