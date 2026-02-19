#!/bin/bash
set -euo pipefail

# 01-check-environment.sh — Detect OS, Bun, container runtimes, existing config

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/logs/setup.log"

mkdir -p "$PROJECT_ROOT/logs"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [check-environment] $*" >> "$LOG_FILE"; }

log "Starting environment check"

# Detect platform
UNAME=$(uname -s)
case "$UNAME" in
  Darwin*) PLATFORM="macos" ;;
  Linux*)  PLATFORM="linux" ;;
  *)       PLATFORM="unknown" ;;
esac
log "Platform: $PLATFORM ($UNAME)"

# Check Bun
BUN_OK="false"
BUN_VERSION="not_found"
if command -v bun >/dev/null 2>&1; then
  BUN_VERSION=$(bun --version 2>/dev/null)
  MAJOR=$(echo "$BUN_VERSION" | cut -d. -f1)
  if [ "$MAJOR" -ge 1 ] 2>/dev/null; then
    BUN_OK="true"
  fi
  log "Bun $BUN_VERSION found (major=$MAJOR, ok=$BUN_OK)"
else
  log "Bun not found"
fi

# Check Apple Container
APPLE_CONTAINER="not_found"
if command -v container >/dev/null 2>&1; then
  APPLE_CONTAINER="installed"
  log "Apple Container: installed ($(which container))"
else
  log "Apple Container: not found"
fi

# Check Docker
DOCKER="not_found"
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    DOCKER="running"
    log "Docker: running"
  else
    DOCKER="installed_not_running"
    log "Docker: installed but not running"
  fi
else
  log "Docker: not found"
fi

# Check existing config
HAS_ENV="false"
if [ -f "$PROJECT_ROOT/.env" ]; then
  HAS_ENV="true"
  log ".env file found"
fi

HAS_AUTH="false"
if [ -d "$PROJECT_ROOT/store/auth" ] && [ "$(ls -A "$PROJECT_ROOT/store/auth" 2>/dev/null)" ]; then
  HAS_AUTH="true"
  log "WhatsApp auth credentials found"
fi

HAS_REGISTERED_GROUPS="false"
if [ -f "$PROJECT_ROOT/data/registered_groups.json" ]; then
  HAS_REGISTERED_GROUPS="true"
  log "Registered groups config found (JSON)"
elif [ -f "$PROJECT_ROOT/store/messages.db" ]; then
  RG_COUNT=$(sqlite3 "$PROJECT_ROOT/store/messages.db" "SELECT COUNT(*) FROM registered_groups" 2>/dev/null || echo "0")
  if [ "$RG_COUNT" -gt 0 ] 2>/dev/null; then
    HAS_REGISTERED_GROUPS="true"
    log "Registered groups found in database ($RG_COUNT)"
  fi
fi

log "Environment check complete"

# Output structured status block
cat <<EOF
=== NANOCLAW SETUP: CHECK_ENVIRONMENT ===
PLATFORM: $PLATFORM
BUN_VERSION: $BUN_VERSION
BUN_OK: $BUN_OK
APPLE_CONTAINER: $APPLE_CONTAINER
DOCKER: $DOCKER
HAS_ENV: $HAS_ENV
HAS_AUTH: $HAS_AUTH
HAS_REGISTERED_GROUPS: $HAS_REGISTERED_GROUPS
STATUS: success
LOG: logs/setup.log
=== END ===
EOF

# Exit 2 if Bun is missing or too old
if [ "$BUN_OK" = "false" ]; then
  exit 2
fi
