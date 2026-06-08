#!/usr/bin/env bash
# Install opencode-ntfy plugin into your OpenCode configuration.
# Usage: ./install.sh [--topic TOPIC] [--server URL] [--allow-insecure] [--token TOKEN]
#
# Options:
#   --topic TOPIC         ntfy topic to publish to (default: "opencode")
#   --server URL          ntfy server URL (default: "https://ntfy.sh")
#   --allow-insecure      Allow self-signed TLS certificates
#   --token TOKEN         Bearer token for ntfy authentication
#
# Examples:
#   ./install.sh                                          # defaults: https://ntfy.sh, topic "opencode"
#   ./install.sh --server https://ntfy.doopelab.mad       # self-hosted server
#   ./install.sh --server https://ntfy.example.com --allow-insecure --topic my-topic

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
CONFIG_FILE="${OPENCODE_CONFIG_DIR}/notification-ntfy.json"
OPENCODE_JSON="${OPENCODE_CONFIG_DIR}/opencode.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

TOPIC="opencode"
SERVER="https://ntfy.sh"
ALLOW_INSECURE="false"
TOKEN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --topic)
      TOPIC="$2"; shift 2 ;;
    --server)
      SERVER="${2%/}"; shift 2 ;;
    --allow-insecure)
      ALLOW_INSECURE="true"; shift ;;
    --token)
      TOKEN="$2"; shift 2 ;;
    *)
      log_error "Unknown option: $1"
      echo "Usage: $0 [--topic TOPIC] [--server URL] [--allow-insecure] [--token TOKEN]" >&2
      exit 1
      ;;
  esac
done

echo "============================================"
echo "  opencode-ntfy installer"
echo "============================================"
echo ""
echo "  Topic:         ${TOPIC}"
echo "  Server:        ${SERVER}"
echo "  Allow Insecure: ${ALLOW_INSECURE}"
echo "  Token:         ${TOKEN:+***configured***}"
echo ""

# 1. Build the plugin
log_info "Building plugin..."
cd "$SCRIPT_DIR"
if command -v bun &>/dev/null; then
  bun run build
elif command -v npx &>/dev/null; then
  npx tsc
else
  log_error "Neither bun nor npx found. Install bun or node to build the plugin."
  exit 1
fi
log_info "Build complete."

# 2. Install into OpenCode's node_modules
log_info "Installing plugin into OpenCode configuration..."
mkdir -p "$OPENCODE_CONFIG_DIR"

cd "$OPENCODE_CONFIG_DIR"
if [ ! -f package.json ]; then
  log_info "Initialising OpenCode package.json..."
  echo '{"dependencies":{}}' > package.json
fi

bun add "${SCRIPT_DIR}" 2>&1 | tail -1
log_info "Plugin installed."

# 3. Add plugin to opencode.json if not already present
if [ -f "$OPENCODE_JSON" ]; then
  if grep -q '"opencode-ntfy"' "$OPENCODE_JSON"; then
    log_info "Plugin already registered in opencode.json."
  else
    log_warn "Plugin not found in opencode.json. Add it manually:"
    log_warn '  "plugin": ["opencode-ntfy"]'
  fi
else
  log_warn "No opencode.json found at ${OPENCODE_JSON}. Create one with:"
  log_warn '  { "plugin": ["opencode-ntfy"] }'
fi

# 4. Write notification config
log_info "Writing notification config to ${CONFIG_FILE}..."
BACKEND_JSON=$(cat <<EOF
{
  "backend": {
    "topic": "${TOPIC}",
    "server": "${SERVER}",
    "allowInsecure": ${ALLOW_INSECURE}
EOF
)
if [ -n "$TOKEN" ]; then
  BACKEND_JSON="${BACKEND_JSON},
    \"token\": \"${TOKEN}\""
fi
BACKEND_JSON="${BACKEND_JSON}
  }
}"

echo "$BACKEND_JSON" > "$CONFIG_FILE"
log_info "Config written."

# 5. Verify
echo ""
log_info "Verifying installation..."
if [ -L "${OPENCODE_CONFIG_DIR}/node_modules/opencode-ntfy" ] || \
   [ -d "${OPENCODE_CONFIG_DIR}/node_modules/opencode-ntfy" ]; then
  log_info "opencode-ntfy is present in OpenCode modules."
else
  log_error "Plugin not found in OpenCode modules. Something went wrong."
  exit 1
fi

if [ -f "$CONFIG_FILE" ]; then
  log_info "Notification config present at ${CONFIG_FILE}."
else
  log_error "Config file was not created."
  exit 1
fi

echo ""
echo "============================================"
echo "  Installation complete!"
echo ""
echo "  Restart OpenCode for changes to take effect."
echo "============================================"
