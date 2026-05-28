#!/bin/bash
# Start hermes-agent gateway + hermes-webui services
# Usage: start-services.sh <port>

set -e

PORT="${1:-8787}"
HERMES_DIR="/opt/hermes"
VENV_BIN="${HERMES_DIR}/venv/bin"
LOG_DIR="/root/.hermes/logs"
PID_DIR="/run/hermes"

export PATH="${VENV_BIN}:/root/.local/bin:${PATH}"
export HERMES_HOME="/root/.hermes"
export HERMES_WEBUI_AGENT_DIR="${HERMES_DIR}/hermes-agent"
export HERMES_WEBUI_PORT="${PORT}"
export HERMES_WEBUI_HOST="0.0.0.0"

mkdir -p "${LOG_DIR}" "${PID_DIR}"

is_running() {
    local pidfile="$1"
    if [ -f "${pidfile}" ]; then
        local pid
        pid=$(cat "${pidfile}")
        if kill -0 "${pid}" 2>/dev/null; then
            return 0
        fi
        rm -f "${pidfile}"
    fi
    return 1
}

start_agent() {
    if is_running "${PID_DIR}/agent.pid"; then
        echo "hermes-agent already running"
        return 0
    fi

    echo "Starting hermes-agent gateway..."
    cd "${HERMES_DIR}/hermes-agent"
    nohup "${VENV_BIN}/python" -m hermes_cli.main gateway run --replace \
        > "${LOG_DIR}/agent.log" 2>&1 &
    echo $! > "${PID_DIR}/agent.pid"
    echo "hermes-agent started (PID: $!)"
}

start_webui() {
    if is_running "${PID_DIR}/webui.pid"; then
        echo "hermes-webui already running"
        return 0
    fi

    echo "Starting hermes-webui on port ${PORT}..."
    cd "${HERMES_DIR}/hermes-webui"
    nohup "${VENV_BIN}/python" server.py \
        > "${LOG_DIR}/webui.log" 2>&1 &
    echo $! > "${PID_DIR}/webui.pid"
    echo "hermes-webui started (PID: $!)"
}

start_agent
start_webui

echo "All services started. WebUI available at http://localhost:${PORT}"
