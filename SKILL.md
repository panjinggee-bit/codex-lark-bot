---
name: codex-lark-bot
description: Connect local Codex CLI or Claude Code to Feishu/Lark, install lark-cli when missing, create or configure a Feishu/Lark custom app bot, initialize app credentials, run OAuth/device login, verify scopes, install Lark agent skills where applicable, start a local Feishu-to-agent bridge, listen for bot messages, invoke Claude/Codex, and reply in Feishu. Use when the user asks to make Codex or Claude Code work with Feishu/Lark, automatically create a Feishu robot/bot, configure lark-cli for local coding agents, diagnose agent-to-Lark connectivity, or set up bot messaging automation.
---

# Codex Lark Bot

Use this skill to connect local Codex CLI and/or Claude Code to Feishu/Lark with `lark-cli`, provision a custom app bot, and run a local bridge that turns Feishu/Lark bot messages into local agent replies.

## One-Command Install

Preferred npm-style command:

```powershell
npx github:panjinggee-bit/codex-lark-bot
```

This command is the one-step path: choose one local agent, connect or reuse a Feishu/Lark app/bot through the official QR/browser flow when needed, then start the local bridge.

To start only the local bridge later:

```powershell
npx github:panjinggee-bit/codex-lark-bot bridge
```

To keep the bridge running after the terminal closes, install it as a Windows background task:

```powershell
npx github:panjinggee-bit/codex-lark-bot install-service
```

Manage it later with:

```powershell
npx github:panjinggee-bit/codex-lark-bot status-service
npx github:panjinggee-bit/codex-lark-bot stop-service
npx github:panjinggee-bit/codex-lark-bot start-service
npx github:panjinggee-bit/codex-lark-bot uninstall-service
```

After publishing this package to npm, the command becomes:

```powershell
npx codex-lark-bot
```

Fallback raw PowerShell command:

```powershell
powershell -ExecutionPolicy Bypass -Command "iwr -UseBasicParsing https://raw.githubusercontent.com/panjinggee-bit/codex-lark-bot/main/install.ps1 | iex"
```

The installer clones or updates this skill into `~/.codex/skills/codex-lark-bot`, then starts the interactive setup wizard. The wizard asks:

- Which single local agent to connect: Claude Code or Codex CLI.
- It then calls the official `lark-cli config init --new` flow. That Feishu/Lark flow can let the user scan/confirm login and choose an existing app/bot or create a new one.
- After setup, it installs and starts the background bridge service so Feishu/Lark can continue calling the local agent after the terminal closes.

To connect both Claude Code and Codex CLI cleanly, run the wizard twice and bind each agent to its own Feishu/Lark bot/app. A single bridge process has exactly one answering agent.

## Core Workflow

1. Check local tools and install `lark-cli` if missing.

   ```powershell
   Get-Command node
   Get-Command npm
   Get-Command codex
   Get-Command claude
   Get-Command lark-cli -ErrorAction SilentlyContinue
   npm install -g @larksuite/cli
   lark-cli --version
   lark-cli doctor --offline
   ```

   On macOS/Linux, use the same package manager idea:

   ```bash
   npm install -g @larksuite/cli
   ```

2. For Claude Code, install the official Lark CLI agent skills after `lark-cli` is available:

   ```powershell
   npx skills add larksuite/cli -g -y
   ```

   For Codex, this skill is the Codex-side workflow. Do not try to install Claude-specific skills into Codex unless the user explicitly asks for cross-tool migration.

3. If the user already has an app, configure it non-interactively:

   ```powershell
   $secret = Read-Host "App Secret" -AsSecureString
   $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
     [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
   )
   $plain | lark-cli config init --brand feishu --app-id <app_id> --app-secret-stdin
   ```

4. For interactive setup, prefer the official CLI bootstrap and let the Feishu/Lark flow decide whether to reuse an existing app/bot or create a new one:

   ```powershell
   lark-cli config init --new --brand feishu --lang zh
   ```

   This command may block while the user completes setup in the browser. Surface the verification URL or browser instructions from the command output. Treat this as semi-automated: Codex starts the app/bot connection flow, but the user may need to scan a QR code, choose an existing app, create a new app, choose a tenant, or approve permissions.

5. Verify configuration and auth:

   ```powershell
   lark-cli config show
   lark-cli auth status
   lark-cli auth scopes --format pretty
   lark-cli doctor
   ```

6. If user access is needed, run device login:

   ```powershell
   lark-cli auth login
   ```

7. Validate the bot by creating a chat or sending a message:

   ```powershell
   lark-cli contact +search-user --query "<name-or-email>" --format table
   lark-cli im +chat-create --name "Codex Bot Test" --users "<ou_xxx>" --type private --set-bot-manager --format pretty
   lark-cli im +messages-send --chat-id "<oc_xxx>" --text "Codex bot connection OK"
   ```

8. Start the local bridge when the user wants Feishu/Lark messages to trigger a local agent:

   ```powershell
   npx github:panjinggee-bit/codex-lark-bot bridge
   ```

   The bridge listens to `im.message.receive_v1`, handles text messages delivered to the bot, calls the selected local agent, and replies with `lark-cli im +messages-reply`.

## Scripted Bootstrap

Prefer the npm-style commands for repeatable setup and diagnostics:

```powershell
npx github:panjinggee-bit/codex-lark-bot
npx github:panjinggee-bit/codex-lark-bot bridge
npx github:panjinggee-bit/codex-lark-bot install-service
npx github:panjinggee-bit/codex-lark-bot status-service
npx github:panjinggee-bit/codex-lark-bot stop-service
npx github:panjinggee-bit/codex-lark-bot start-service
npx github:panjinggee-bit/codex-lark-bot uninstall-service
```

If calling the local script directly is necessary, resolve it from the user's home directory instead of hardcoding a machine-specific path:

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\.codex\skills\codex-lark-bot\scripts\codex_lark_bootstrap.ps1" -Mode bridge -Agent claude
```

The script never accepts `app_secret` as a command-line argument. For `existing-app`, it prompts securely and passes the secret through stdin.

`-InstallIfMissing` installs `@larksuite/cli` with npm if `lark-cli` is absent. `-Agent claude` also runs `npx skills add larksuite/cli -g -y` so Claude Code receives the official Lark skills. `-Mode interactive` now performs setup and starts the bridge in one run. `-Mode bridge` starts a long-running local listener and also bootstraps Feishu/Lark config if no app is configured; keep its terminal open. The interactive wizard intentionally binds one bot/app to one answering agent; use separate runs for Claude Code and Codex CLI.

## Local Bridge

The bridge is required for real Feishu/Lark-to-agent interaction. App creation alone only configures credentials.

```powershell
npx github:panjinggee-bit/codex-lark-bot bridge
```

Bridge behavior:

- Subscribes to `im.message.receive_v1` with a Node-based UTF-8 event reader around `lark-cli event +subscribe --quiet`.
- Handles text messages delivered to the bot and ignores empty, non-text, duplicate, and bot-sender messages.
- Invokes Claude Code with `claude --print --permission-mode plan`.
- Invokes Codex CLI with `codex exec --skip-git-repo-check -` from the user's home directory, writing the prompt to Codex stdin as a UTF-8 Buffer to preserve Chinese text.
- Adds a small reaction to the user's message when processing starts if the app has reaction permissions.
- Replies through `lark-cli im +messages-reply --as bot`.
- Keeps a small in-memory de-duplication cache for recent `message_id` values.

The local machine must stay online while the bridge is running. If Feishu/Lark does not deliver messages, verify the app has bot capability, event subscription includes `im.message.receive_v1`, WebSocket event receiving is enabled, the app is published/installed, and the bridge terminal is still running.

## Background Service

Install a background service when the bridge should survive terminal close:

```powershell
npx github:panjinggee-bit/codex-lark-bot install-service
```

On Windows this creates a Task Scheduler task that runs a generated `.cmd` launcher with the current PATH captured, so npm shims such as `lark-cli`, `codex`, and `claude` still resolve after the terminal closes. On macOS this creates a LaunchAgent in `~/Library/LaunchAgents` with PATH explicitly injected. The service starts immediately after installation and writes logs under `~/.codex/skills/codex-lark-bot/logs/bridge-<agent>.log`.

Use `status-service`, `stop-service`, `start-service`, and `uninstall-service` to manage it. The computer and user session still need to be online; this is a local background bridge, not a cloud-hosted bot.

## Permission Guidance

When bot IM features fail, inspect enabled scopes first:

```powershell
lark-cli auth scopes --format pretty
lark-cli auth check --help
```

Common capabilities usually require IM send/chat scopes and contact read scopes. If a command reports missing scopes, tell the user exactly which scope is missing and ask them to enable it in the app console, then publish or reinstall the app if Feishu requires it.

## Operating Rules

- Prefer `lark-cli` over raw HTTP when a command exists.
- Use `--as bot` for bot-only IM actions and `--as user` for user mailbox/search actions when required.
- Never print, store, or pass `app_secret` on a command line; use `--app-secret-stdin`.
- If `lark-cli` is missing, install `@larksuite/cli` through npm before continuing. If Node/npm is missing, stop and ask the user to install Node.js or approve their preferred package manager.
- For Claude Code, verify `claude` exists and install the Lark CLI skills with `npx skills add larksuite/cli -g -y`.
- Do not claim full automation if the Open Platform requires human confirmation, tenant selection, app publishing, or administrator approval.
- After setup, run `lark-cli doctor` and one real bot action such as `+messages-send` or `+chat-create` before declaring credentials complete.
- Do not declare Feishu/Lark connected to a local agent until the bridge receives a message, invokes the selected agent, and replies in Feishu/Lark.
- If the user asks to connect Codex or Claude Code itself to the bot, clarify the intended runtime: local one-shot CLI commands, recurring automation, webhook/event listener, or MCP/skill-based operation.

## References

Read `references/feishu-bot-checklist.md` when troubleshooting setup failures, missing scopes, or deciding whether the remaining step is local CLI work or Feishu console approval.
