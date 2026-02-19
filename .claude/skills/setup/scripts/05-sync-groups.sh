#!/bin/bash
set -euo pipefail

# 05-sync-groups.sh — Use Telegram Bot API getUpdates to discover groups, write to DB, exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/logs/setup.log"

mkdir -p "$PROJECT_ROOT/logs"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [sync-groups] $*" >> "$LOG_FILE"; }

cd "$PROJECT_ROOT"

# Load bot token from .env
if [ -f "$PROJECT_ROOT/.env" ]; then
  TELEGRAM_BOT_TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$PROJECT_ROOT/.env" | cut -d= -f2- | tr -d '"' | tr -d "'")
fi

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
  log "No TELEGRAM_BOT_TOKEN found in .env"
  cat <<EOF
=== NANOCLAW SETUP: SYNC_GROUPS ===
SYNC: failed
GROUPS_IN_DB: 0
STATUS: failed
ERROR: no_bot_token
LOG: logs/setup.log
=== END ===
EOF
  exit 1
fi

# Use Telegram getUpdates API to discover chats the bot has seen
log "Fetching chat metadata from Telegram getUpdates"
SYNC="failed"

SYNC_OUTPUT=$(bun -e "
import { Database } from 'bun:sqlite';
import path from 'path';
import fs from 'fs';

const token = process.env.TELEGRAM_BOT_TOKEN;
const dbPath = path.join('store', 'messages.db');

if (!fs.existsSync(path.dirname(dbPath))) {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
}

const db = new Database(dbPath);
db.exec('PRAGMA journal_mode = WAL');
db.exec('CREATE TABLE IF NOT EXISTS chats (jid TEXT PRIMARY KEY, name TEXT, last_message_time TEXT)');

const upsert = db.prepare(
  'INSERT INTO chats (jid, name, last_message_time) VALUES (?, ?, ?) ON CONFLICT(jid) DO UPDATE SET name = excluded.name'
);

try {
  const res = await fetch('https://api.telegram.org/bot' + token + '/getUpdates?limit=100&allowed_updates=[\"message\"]');
  const data = await res.json();

  if (!data.ok) {
    console.error('API_ERROR:' + JSON.stringify(data.description));
    process.exit(1);
  }

  const seen = new Map();
  for (const update of data.result || []) {
    const chat = update.message?.chat;
    if (!chat) continue;
    const jid = 'tg:' + chat.id;
    const name = chat.title || chat.first_name || chat.username || String(chat.id);
    seen.set(jid, name);
  }

  const now = new Date().toISOString();
  for (const [jid, name] of seen) {
    upsert.run(jid, name, now);
  }

  console.log('SYNCED:' + seen.size);
} catch (err) {
  console.error('FETCH_ERROR:' + err.message);
  process.exit(1);
} finally {
  db.close();
}
" 2>&1) || true

log "Sync output: $SYNC_OUTPUT"

if echo "$SYNC_OUTPUT" | grep -q "SYNCED:"; then
  SYNC="success"
fi

# Check for chats in DB
GROUPS_IN_DB=0
if [ -f "$PROJECT_ROOT/store/messages.db" ]; then
  GROUPS_IN_DB=$(sqlite3 "$PROJECT_ROOT/store/messages.db" "SELECT COUNT(*) FROM chats WHERE jid LIKE 'tg:%'" 2>/dev/null || echo "0")
  log "Chats found in DB: $GROUPS_IN_DB"
fi

STATUS="success"
if [ "$SYNC" != "success" ]; then
  STATUS="failed"
fi

cat <<EOF
=== NANOCLAW SETUP: SYNC_GROUPS ===
SYNC: $SYNC
GROUPS_IN_DB: $GROUPS_IN_DB
STATUS: $STATUS
LOG: logs/setup.log
=== END ===
EOF

if [ "$STATUS" = "failed" ]; then
  exit 1
fi
