#!/bin/bash
set -euo pipefail

# 04-auth-telegram.sh — Verify Telegram bot token is configured

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/logs/setup.log"

mkdir -p "$PROJECT_ROOT/logs"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [auth-telegram] $*" >> "$LOG_FILE"; }

cd "$PROJECT_ROOT"

emit_status() {
  local auth_status="$1" status="$2" error="${3:-}"
  cat <<EOF
=== NANOCLAW SETUP: AUTH_TELEGRAM ===
AUTH_STATUS: $auth_status
STATUS: $status
EOF
  [ -n "$error" ] && echo "ERROR: $error"
  cat <<EOF
LOG: logs/setup.log
=== END ===
EOF
}

log "Checking Telegram bot token configuration"

# Check if .env file exists
if [ ! -f "$PROJECT_ROOT/.env" ]; then
  log "No .env file found"
  emit_status "missing" "needs_input" "no_env_file"
  exit 0
fi

# Check if TELEGRAM_BOT_TOKEN is set
TOKEN=$(grep -E "^TELEGRAM_BOT_TOKEN=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2- | tr -d '[:space:]' || true)

if [ -z "$TOKEN" ]; then
  log "TELEGRAM_BOT_TOKEN not set in .env"
  emit_status "missing" "needs_input" "no_token"
  exit 0
fi

# Validate token format (should be like 123456789:ABC-DEF...)
if ! echo "$TOKEN" | grep -qE "^[0-9]+:[A-Za-z0-9_-]+$"; then
  log "TELEGRAM_BOT_TOKEN format looks invalid"
  emit_status "invalid" "needs_input" "invalid_token_format"
  exit 0
fi

# Optionally verify token with Telegram API
if command -v curl >/dev/null 2>&1; then
  log "Verifying token with Telegram API"
  RESPONSE=$(curl -s "https://api.telegram.org/bot${TOKEN}/getMe" 2>/dev/null || echo '{"ok":false}')
  if echo "$RESPONSE" | grep -q '"ok":true'; then
    BOT_NAME=$(echo "$RESPONSE" | grep -o '"username":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    log "Token valid, bot username: @$BOT_NAME"
    cat <<EOF
=== NANOCLAW SETUP: AUTH_TELEGRAM ===
AUTH_STATUS: authenticated
BOT_USERNAME: @$BOT_NAME
STATUS: success
LOG: logs/setup.log
=== END ===
EOF
    exit 0
  else
    log "Token verification failed: $RESPONSE"
    emit_status "invalid" "needs_input" "token_rejected_by_telegram"
    exit 0
  fi
fi

# If no curl, just report token is present
log "Token found (curl not available for verification)"
emit_status "configured" "success"
exit 0
