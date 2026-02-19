---
name: setup
description: Run initial NanoClaw setup. Use when user wants to install dependencies, configure Telegram bot token, register their main channel, or start the background services. Triggers on "setup", "install", "configure nanoclaw", or first-time setup requests.
---

# NanoClaw Setup

Run setup scripts automatically. Only pause when user action is required (Telegram bot token, configuration choices). Scripts live in `.claude/skills/setup/scripts/` and emit structured status blocks to stdout. Verbose logs go to `logs/setup.log`.

**Principle:** When something is broken or missing, fix it. Don't tell the user to go fix it themselves unless it genuinely requires their manual action (e.g. scanning a QR code, pasting a secret token). If a dependency is missing, install it. If a service won't start, diagnose and repair. Ask the user for permission when needed, then do the work.

**UX Note:** Use `AskUserQuestion` for all user-facing questions.

## 1. Check Environment

Run `./.claude/skills/setup/scripts/01-check-environment.sh` and parse the status block.

- If HAS_TELEGRAM_TOKEN=true → note that Telegram bot token exists, offer to skip step 5
- If HAS_REGISTERED_GROUPS=true → note existing config, offer to skip or reconfigure
- Record PLATFORM, APPLE_CONTAINER, and DOCKER values for step 3

**If BUN_OK=false:**

Bun is missing or too old. Ask the user if they'd like you to install it:

- macOS/Linux: `curl -fsSL https://bun.sh/install | bash`

After installing Bun, re-run the environment check to confirm BUN_OK=true.

## 2. Install Dependencies

Run `./.claude/skills/setup/scripts/02-install-deps.sh` and parse the status block.

**If failed:** Read the tail of `logs/setup.log` to diagnose. Common fixes to try automatically:
1. Delete `node_modules` and `package-lock.json`, then re-run the script
2. If permission errors: suggest running with corrected permissions
3. If specific package fails to build (native modules like better-sqlite3): install build tools (`xcode-select --install` on macOS, `build-essential` on Linux), then retry

Only ask the user for help if multiple retries fail with the same error.

## 3. Container Runtime

### 3a. Choose runtime

Use the environment check results from step 1 to decide which runtime to use:

- PLATFORM=linux → Docker
- PLATFORM=macos + APPLE_CONTAINER=installed → apple-container
- PLATFORM=macos + DOCKER=running + APPLE_CONTAINER=not_found → Docker
- PLATFORM=macos + DOCKER=installed_not_running → start Docker: `open -a Docker`. Wait 15s, re-check with `docker info`. If still not running, tell the user Docker is starting up and poll a few more times.
- Neither available → AskUserQuestion: Apple Container (recommended for macOS) vs Docker?
  - Apple Container: tell user to download from https://github.com/apple/container/releases and install the .pkg. Wait for confirmation, then verify with `container --version`.
  - Docker on macOS: install via `brew install --cask docker`, then `open -a Docker` and wait for it to start. If brew not available, direct to Docker Desktop download.
  - Docker on Linux: install with `curl -fsSL https://get.docker.com | sh && sudo usermod -aG docker $USER`. Note: user may need to log out/in for group membership.

### 3b. Docker conversion gate (REQUIRED before building)

**If the chosen runtime is Docker**, you MUST check whether the source code has already been converted from Apple Container to Docker. Do NOT skip this step. Run:

```bash
grep -q 'container system status' src/index.ts && echo "NEEDS_CONVERSION" || echo "ALREADY_CONVERTED"
```

Check these three files for Apple Container references:
- `src/index.ts` — look for `container system status` or `ensureContainerSystemRunning`
- `src/container-runner.ts` — look for `spawn('container'`
- `container/build.sh` — look for `container build`

**If ANY of those Apple Container references exist**, the source code has NOT been converted. You MUST run the `/convert-to-docker` skill NOW, before proceeding to the build step. Do not attempt to build the container image until the conversion is complete.

**If none of those references exist** (i.e. the code already uses `docker info`, `spawn('docker'`, `docker build`), the conversion has already been done. Continue to 3c.

### 3c. Build and test

Run `./.claude/skills/setup/scripts/03-setup-container.sh --runtime <chosen>` and parse the status block.

**If BUILD_OK=false:** Read `logs/setup.log` tail for the build error.
- If it's a cache issue (stale layers): run `container builder stop && container builder rm && container builder start` (Apple Container) or `docker builder prune -f` (Docker), then retry.
- If Dockerfile syntax or missing files: diagnose from the log and fix.
- Retry the build script after fixing.

**If TEST_OK=false but BUILD_OK=true:** The image built but won't run. Check logs — common cause is runtime not fully started. Wait a moment and retry the test.

## 4. Claude Authentication (No Script)

If HAS_ENV=true from step 1, read `.env` and check if it already has `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`. If so, confirm with user: "You already have Claude credentials configured. Want to keep them or reconfigure?" If keeping, skip to step 5.

AskUserQuestion: Claude subscription (Pro/Max) vs Anthropic API key?

**Subscription:** Tell the user:
1. Open another terminal and run: `claude setup-token`
2. Copy the token it outputs
3. Add it to the `.env` file in the project root: `CLAUDE_CODE_OAUTH_TOKEN=<token>`
4. Let me know when done

Do NOT ask the user to paste the token into the chat. Do NOT use AskUserQuestion to collect the token. Just tell them what to do, then wait for confirmation that they've added it to `.env`. Once confirmed, verify the `.env` file has the key.

**API key:** Tell the user to add `ANTHROPIC_API_KEY=<key>` to the `.env` file in the project root, then let you know when done. Once confirmed, verify the `.env` file has the key.

## 5. Telegram Bot Authentication

Run `./.claude/skills/setup/scripts/04-auth-telegram.sh` and parse the status block.

If AUTH_STATUS=authenticated → note the BOT_USERNAME and skip ahead.

If AUTH_STATUS=missing or needs_input:
- Tell the user: "You need a Telegram bot token. Create one by messaging @BotFather on Telegram, send `/newbot`, and follow the steps. Then add `TELEGRAM_BOT_TOKEN=<your_token>` to the `.env` file in the project root."
- Do NOT ask the user to paste the token into the chat. Wait for them to confirm they've added it to `.env`.
- Once confirmed, re-run the auth script to verify.

If AUTH_STATUS=invalid → token format is wrong or rejected by Telegram. Tell the user to double-check the token from @BotFather and update `.env`.

## 6. Configure Trigger and Channel Type

AskUserQuestion: What trigger word? (default: Andy). In group chats, messages starting with @TriggerWord go to Claude. In the main channel (your personal DM with the bot), no prefix needed.

AskUserQuestion: Main channel type?
1. Personal DM with the bot — Recommended. You message the bot directly in Telegram.
2. Group chat — Add the bot to a Telegram group.

## 7. Sync and Select Group (If Group Channel)

**For personal DM:** The chat ID will be auto-detected when you first message the bot. For now, use your Telegram user ID as a placeholder — run `./.claude/skills/setup/scripts/05-sync-groups.sh` after the service starts to get the real ID.

**For group:**
1. Add the bot to the Telegram group first, then run `./.claude/skills/setup/scripts/05-sync-groups.sh` (Bash timeout: 60000ms)
2. **If BUILD=failed:** Read `logs/setup.log`, fix the TypeScript error, re-run.
3. **If GROUPS_IN_DB=0:** Check `logs/setup.log`. Common causes: bot not added to group yet, or service not running.
4. Run `./.claude/skills/setup/scripts/05b-list-groups.sh` to get groups (pipe-separated JID|name lines). Do NOT display the output to the user.
5. Pick the most likely candidates and present them as AskUserQuestion options — show names only, not JIDs. Include an "Other" option if their group isn't listed.

## 8. Register Channel

Run `./.claude/skills/setup/scripts/06-register-channel.sh` with args:
- `--jid "JID"` — from step 7
- `--name "main"` — always "main" for the first channel
- `--trigger "@TriggerWord"` — from step 6
- `--folder "main"` — always "main" for the first channel
- `--no-trigger-required` — if personal chat, DM, or solo group
- `--assistant-name "Name"` — if trigger word differs from "Andy"

## 9. Mount Allowlist

AskUserQuestion: Want the agent to access directories outside the NanoClaw project? (Git repos, project folders, documents, etc.)

**If no:** Run `./.claude/skills/setup/scripts/07-configure-mounts.sh --empty`

**If yes:** Collect directory paths and permissions (read-write vs read-only). Ask about non-main group read-only restriction (recommended: yes). Build the JSON and pipe it to the script:

`echo '{"allowedRoots":[...],"blockedPatterns":[],"nonMainReadOnly":true}' | ./.claude/skills/setup/scripts/07-configure-mounts.sh`

Tell user how to grant a group access: add `containerConfig.additionalMounts` to their entry in `data/registered_groups.json`.

## 10. Start Service

If the service is already running (check `launchctl list | grep nanoclaw` on macOS), unload it first: `launchctl unload ~/Library/LaunchAgents/com.nanoclaw.plist` — then proceed with a clean install.

Run `./.claude/skills/setup/scripts/08-setup-service.sh` and parse the status block.

**If SERVICE_LOADED=false:**
- Read `logs/setup.log` for the error.
- Common fix: plist already loaded with different path. Unload the old one first, then re-run.
- On macOS: check `launchctl list | grep nanoclaw` to see if it's loaded with an error status. If the PID column is `-` and the status column is non-zero, the service is crashing. Read `logs/nanoclaw.error.log` for the crash reason and fix it (common: wrong Bun path, missing .env, missing bot token).
- On Linux: check `systemctl --user status nanoclaw` for the error and fix accordingly.
- Re-run the setup-service script after fixing.

## 11. Verify

Run `./.claude/skills/setup/scripts/09-verify.sh` and parse the status block.

**If STATUS=failed, fix each failing component:**
- SERVICE=stopped → restart: `launchctl kickstart -k gui/$(id -u)/com.nanoclaw` (macOS) or `systemctl --user restart nanoclaw` (Linux). Re-check.
- SERVICE=not_found → re-run step 10.
- CREDENTIALS=missing → re-run step 4.
- TELEGRAM_TOKEN=missing → re-run step 5.
- REGISTERED_GROUPS=0 → re-run steps 7-8.
- MOUNT_ALLOWLIST=missing → run `./.claude/skills/setup/scripts/07-configure-mounts.sh --empty` to create a default.

After fixing, re-run `09-verify.sh` to confirm everything passes.

Tell user to test: send a message in their registered chat (with or without trigger depending on channel type).

Show the log tail command: `tail -f logs/nanoclaw.log`

## Troubleshooting

**Service not starting:** Check `logs/nanoclaw.error.log`. Common causes: wrong Bun path in plist (re-run step 10), missing `.env` (re-run step 4), missing Telegram bot token (re-run step 5).

**Container agent fails ("Claude Code process exited with code 1"):** Ensure the container runtime is running — start it: `container system start` (Apple Container) or `open -a Docker` (macOS Docker). Check container logs in `groups/main/logs/container-*.log`.

**No response to messages:** Verify the trigger pattern matches. Main channel (personal DM) doesn't need a prefix. Check the registered chat ID in the database: `sqlite3 store/messages.db "SELECT * FROM registered_groups"`. Check `logs/nanoclaw.log`.

**Telegram bot not receiving messages:** Ensure the bot token is valid in `.env`. For groups, make sure the bot is actually a member of the group. Check `logs/nanoclaw.log` for connection errors.

**Unload service:** `launchctl unload ~/Library/LaunchAgents/com.nanoclaw.plist`
