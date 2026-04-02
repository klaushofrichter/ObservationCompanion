#!/usr/bin/env bash
#
# Upload secrets from .env to GitHub repository secrets
#
# Usage: ./scripts/upload-github-secrets.sh
#
# Requires: GitHub CLI (gh) authenticated with repo access
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Upload Secrets to GitHub Repository"
echo "=========================================="

# Check gh CLI is installed and authenticated
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI is not authenticated. Run 'gh auth login' first.${NC}"
    exit 1
fi

# Check .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: $ENV_FILE not found${NC}"
    exit 1
fi

echo "Reading secrets from: $ENV_FILE"
echo ""

# Function to upload a secret
upload_secret() {
    local gh_secret_name="$1"
    local env_var_name="$2"

    local line=$(grep "^${env_var_name}=" "$ENV_FILE" 2>/dev/null | head -1)

    if [ -z "$line" ]; then
        echo -e "${YELLOW}⚠ Skipping $gh_secret_name - $env_var_name not found in .env${NC}"
        return
    fi

    local value="${line#*=}"
    value="${value#\"}"
    value="${value%\"}"

    if [ -z "$value" ]; then
        echo -e "${YELLOW}⚠ Skipping $gh_secret_name - $env_var_name has empty value${NC}"
        return
    fi

    if [[ "$value" == *$'\n'* ]]; then
        echo -e "${RED}✗ $gh_secret_name contains newlines (not supported)${NC}"
        return 1
    fi

    echo -n "Uploading $gh_secret_name... "
    if printf '%s' "$value" | gh secret set "$gh_secret_name" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
        return 1
    fi
}

echo "--- Test Credentials ---"
upload_secret "TEST_USER" "TEST_USER"
upload_secret "TEST_PASSWORD" "TEST_PASSWORD"

echo ""
echo "--- API Keys ---"
upload_secret "ANTHROPIC_API_KEY" "ANTHROPIC_API_KEY"

echo ""
echo "=========================================="
echo -e "${GREEN}Secret upload complete!${NC}"
echo "=========================================="
echo ""
echo "Verify with: gh secret list"
