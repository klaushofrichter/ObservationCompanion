#!/usr/bin/env bash
#
# Ensures the EEN mobile proxy is running at the configured URL.
# If not running, starts it in the background and waits until ready.
#
# Usage:
#   ./scripts/ensure-proxy.sh
#   PROXY_URL=http://127.0.0.1:3333 ./scripts/ensure-proxy.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROXY_DIR="$(cd "$PROJECT_DIR/../een-mobile-proxy/proxy" 2>/dev/null && pwd)" || true
PROXY_URL="${PROXY_URL:-http://127.0.0.1:3333}"
PROXY_LOG="$PROJECT_DIR/.proxy.log"
MAX_WAIT=30

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

check_proxy() {
    curl -sf "$PROXY_URL/proxy/version" > /dev/null 2>&1
}

if check_proxy; then
    echo -e "${GREEN}Proxy is already running${NC} at $PROXY_URL"
    exit 0
fi

echo -e "${BLUE}Proxy not running at $PROXY_URL — starting it...${NC}"

# Extract port from PROXY_URL
PROXY_PORT=$(echo "$PROXY_URL" | sed -E 's|.*:([0-9]+).*|\1|')
if [ -z "$PROXY_PORT" ]; then
    PROXY_PORT=3333
fi

# Check if something else is using the port and kill it
PORT_PID=$(lsof -ti :"$PROXY_PORT" 2>/dev/null || true)
if [ -n "$PORT_PID" ]; then
    echo -e "${BLUE}Port $PROXY_PORT is in use by PID $PORT_PID — terminating...${NC}"
    kill "$PORT_PID" 2>/dev/null || true
    sleep 1
    # Force kill if still alive
    if kill -0 "$PORT_PID" 2>/dev/null; then
        kill -9 "$PORT_PID" 2>/dev/null || true
        sleep 1
    fi
    echo -e "${GREEN}Port $PROXY_PORT freed${NC}"
fi

if [ -z "$PROXY_DIR" ] || [ ! -f "$PROXY_DIR/package.json" ]; then
    echo -e "${RED}Error:${NC} Cannot find mobile proxy at $PROJECT_DIR/../een-mobile-proxy/proxy/"
    echo "Start it manually: cd <path-to-een-mobile-proxy/proxy> && npm run dev"
    exit 1
fi

# Check node_modules
if [ ! -d "$PROXY_DIR/node_modules" ]; then
    echo -e "${BLUE}Installing proxy dependencies...${NC}"
    (cd "$PROXY_DIR" && npm install)
fi

# Start proxy in background
(cd "$PROXY_DIR" && npm run dev > "$PROXY_LOG" 2>&1) &
PROXY_PID=$!
echo "Started proxy (PID $PROXY_PID), waiting for it to be ready..."

# Wait for proxy to respond
elapsed=0
while [ $elapsed -lt $MAX_WAIT ]; do
    if check_proxy; then
        echo -e "${GREEN}Proxy is ready${NC} at $PROXY_URL (PID $PROXY_PID)"
        echo "$PROXY_PID" > "$PROJECT_DIR/.proxy.pid"
        exit 0
    fi
    # Check if process died
    if ! kill -0 "$PROXY_PID" 2>/dev/null; then
        echo -e "${RED}Error:${NC} Proxy process exited unexpectedly. Log:"
        tail -20 "$PROXY_LOG"
        exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

echo -e "${RED}Error:${NC} Proxy did not become ready within ${MAX_WAIT}s. Log:"
tail -20 "$PROXY_LOG"
kill "$PROXY_PID" 2>/dev/null || true
exit 1
