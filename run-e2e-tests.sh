#!/usr/bin/env bash
#
# Run ObservationCompanion E2E XCUITests on the iOS Simulator.
#
# Acquires OAuth credentials via get-test-token.js, discovers a camera,
# then runs the UI test suite with credentials injected via env vars.
#
# Usage:
#   ./run-e2e-tests.sh
#   PROXY_URL=https://my-proxy.workers.dev ./run-e2e-tests.sh
#   SIMULATOR_ID=XXXX ./run-e2e-tests.sh
#
# Prerequisites:
#   - Mobile proxy running (or auto-started by ensure-proxy.sh)
#   - Node.js + npm installed (for Playwright token acquisition)
#   - Xcode + iOS Simulator available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
PROXY_URL="${PROXY_URL:-http://127.0.0.1:3333}"
CREDENTIALS_FILE="$PROJECT_ROOT/test-credentials.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

cleanup() {
    if [ -f "$CREDENTIALS_FILE" ]; then
        rm -f "$CREDENTIALS_FILE"
        echo -e "${BLUE}Cleaned up${NC} $CREDENTIALS_FILE"
    fi
    if [ -f "$PROJECT_ROOT/e2e-credentials.json" ]; then
        rm -f "$PROJECT_ROOT/e2e-credentials.json"
        echo -e "${BLUE}Cleaned up${NC} e2e-credentials.json"
    fi
}
trap cleanup EXIT

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}ObservationCompanion E2E Tests${NC}"
echo -e "${BLUE}============================================${NC}"
echo "Proxy: $PROXY_URL"
echo ""

# -- 1. Ensure proxy is running
echo -e "${BLUE}1. Ensuring proxy is running...${NC}"
"$PROJECT_ROOT/scripts/ensure-proxy.sh"
echo ""

# -- 2. Check Node dependencies
echo -e "${BLUE}2. Checking Node dependencies...${NC}"
cd "$PROJECT_ROOT"
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
    npx playwright install chromium
fi
echo -e "${GREEN}Dependencies ready${NC}"
echo ""

# -- 3. Acquire test credentials
echo -e "${BLUE}3. Acquiring test credentials...${NC}"
PROXY_URL="$PROXY_URL" node scripts/get-test-token.js
if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo -e "${RED}Error:${NC} Token acquisition failed -- no credentials file"
    exit 1
fi
echo -e "${GREEN}Credentials acquired${NC}"
echo ""

# Parse credentials
export TEST_TOKEN=$(python3 -c "import json; print(json.load(open('$CREDENTIALS_FILE'))['accessToken'])")
export TEST_BASE_URL=$(python3 -c "import json; print(json.load(open('$CREDENTIALS_FILE'))['httpsBaseUrl'])")
export TEST_SESSION_ID=$(python3 -c "import json; print(json.load(open('$CREDENTIALS_FILE'))['sessionId'])")
export TEST_EXPIRES_IN=$(python3 -c "import json; print(json.load(open('$CREDENTIALS_FILE'))['expiresIn'])")

# -- 4. Discover a camera ID
echo -e "${BLUE}4. Discovering camera...${NC}"
CAMERA_RESPONSE=$(curl -sf -H "Authorization: Bearer $TEST_TOKEN" \
    "$TEST_BASE_URL/api/v3.0/cameras?pageSize=1" 2>/dev/null || true)

if [ -z "$CAMERA_RESPONSE" ]; then
    echo -e "${RED}Error:${NC} Could not query cameras API"
    exit 1
fi

export TEST_CAMERA_ID=$(echo "$CAMERA_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('results', [])
if results:
    print(results[0]['id'])
else:
    print('')
")

if [ -z "$TEST_CAMERA_ID" ]; then
    echo -e "${RED}Error:${NC} No cameras found in account"
    exit 1
fi
echo -e "${GREEN}Using camera:${NC} $TEST_CAMERA_ID"

# Write e2e credentials file for XCUITest to read (xcodebuild may not forward env vars)
E2E_CREDS_FILE="$PROJECT_ROOT/e2e-credentials.json"
python3 -c "
import json
creds = json.load(open('$CREDENTIALS_FILE'))
creds['cameraId'] = '$TEST_CAMERA_ID'
# Ensure expiresIn is a string for consistent parsing
creds['expiresIn'] = str(creds.get('expiresIn', 3600))
with open('$E2E_CREDS_FILE', 'w') as f:
    json.dump(creds, f, indent=2)
"
echo -e "${GREEN}Credentials file written${NC} for XCUITest"
echo ""

# -- 5. Find simulator
echo -e "${BLUE}5. Finding simulator...${NC}"
if [ -n "${SIMULATOR_ID:-}" ]; then
    SIMULATOR="$SIMULATOR_ID"
    echo "Using provided SIMULATOR_ID=$SIMULATOR"
else
    SIMULATOR=$(xcrun simctl list devices available -j \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
booted = []
available = []
for runtime, devices in sorted(data['devices'].items(), reverse=True):
    if 'iOS' not in runtime:
        continue
    for d in devices:
        if not d.get('isAvailable', False):
            continue
        if 'iPhone' not in d.get('name', ''):
            continue
        entry = d['udid']
        if d.get('state') == 'Booted':
            booted.append(entry)
        else:
            available.append(entry)
for udid in booted + available:
    print(udid)
    sys.exit(0)
" 2>/dev/null || true)

    if [ -z "$SIMULATOR" ]; then
        echo -e "${RED}Error:${NC} No available iOS simulator found"
        exit 1
    fi

    STATE=$(xcrun simctl list devices -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d['udid'] == '$SIMULATOR':
            print(d['state'])
            sys.exit(0)
")
    if [ "$STATE" != "Booted" ]; then
        echo "Booting simulator $SIMULATOR..."
        xcrun simctl boot "$SIMULATOR" 2>/dev/null || true
    fi

    SIM_NAME=$(xcrun simctl list devices -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d['udid'] == '$SIMULATOR':
            print(d['name'])
            sys.exit(0)
")
    echo "Using simulator: $SIM_NAME ($SIMULATOR)"
fi
echo ""

# -- 6. Run E2E tests
echo -e "${BLUE}6. Running E2E tests...${NC}"
echo ""

cd "$PROJECT_ROOT"

set +e
export TEST_TTL="$TEST_EXPIRES_IN"
xcodebuild test \
    -project ObservationCompanion.xcodeproj \
    -scheme ObservationCompanion \
    -destination "id=$SIMULATOR" \
    -only-testing:ObservationCompanionUITests \
    2>&1 | tee /tmp/e2e-test-output.log \
    | grep -E '(Test Case|Test suite|Executed|passed|failed|\*\* TEST)'
TEST_EXIT=${PIPESTATUS[0]}
set -e

echo ""

# -- 7. Report result
echo -e "${BLUE}============================================${NC}"
if [ $TEST_EXIT -eq 0 ]; then
    echo -e "${GREEN}All E2E tests passed!${NC}"
else
    echo -e "${RED}Some E2E tests failed (exit $TEST_EXIT)${NC}"
    echo "Full log: /tmp/e2e-test-output.log"
fi
echo -e "${BLUE}============================================${NC}"

exit $TEST_EXIT
