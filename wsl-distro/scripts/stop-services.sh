#!/bin/bash
# Stop all hermes services

PID_DIR="/run/hermes"

stop_process() {
    local name="$1"
    local pidfile="${PID_DIR}/${name}.pid"

    if [ -f "${pidfile}" ]; then
        local pid
        pid=$(cat "${pidfile}")
        if kill -0 "${pid}" 2>/dev/null; then
            echo "Stopping ${name} (PID: ${pid})..."
            kill "${pid}" 2>/dev/null
            # Wait up to 5 seconds for graceful shutdown
            for i in $(seq 1 10); do
                if ! kill -0 "${pid}" 2>/dev/null; then
                    break
                fi
                sleep 0.5
            done
            # Force kill if still running
            if kill -0 "${pid}" 2>/dev/null; then
                kill -9 "${pid}" 2>/dev/null
            fi
            echo "${name} stopped"
        else
            echo "${name} not running (stale PID file)"
        fi
        rm -f "${pidfile}"
    else
        echo "${name} not running (no PID file)"
    fi
}

stop_process "webui"
stop_process "agent"

# Also kill any orphaned processes
pkill -f "hermes_cli.main gateway" 2>/dev/null || true
pkill -f "hermes-webui.*server.py" 2>/dev/null || true

echo "All services stopped"
