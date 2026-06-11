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

After setup, start the local bridge with:

```powershell
npx github:panjinggee-bit/codex-lark-bot bridge
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

- Which agent to connect: Claude Code, Codex CLI, or both.
- How to connect the Feishu/Lark bot: existing app credentials or new app/bot creation.
- For an existing app, it asks for App ID and App Secret; App Secret is hidden and passed to `lark-cli` through stdin.
- For a new app, it calls the official `lark-cli config init --new` flow and tells the user to scan or confirm the QR/browser prompt when Feishu/Lark shows one.
- After setup, it asks whether to start the local bridge. The bridge must keep running for Feishu/Lark messages to reach local Claude Code or Codex CLI.

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

4. If the user wants a new bot app, prefer the official CLI bootstrap:

   ```powershell
   lark-cli config init --new --brand feishu --lang zh
   ```

   This command may block while the user completes setup in the browser. Surface the verification URL or browser instructions from the command output. Treat this as semi-automated: Codex starts the app-creation flow, but the user may need to confirm in Feishu Open Platform, choose a tenant, or approve permissions.

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
   powershell -ExecutionPolicy Bypass -File C:\Users\KC\.codex\skills\codex-lark-bot\scripts\codex_lark_bootstrap.ps1 -Mode bridge -Agent claude
   ```

   The bridge listens to `im.message.receive_v1`, handles text messages delivered to the bot, calls the selected local agent, and replies with `lark-cli im +messages-reply`.

## Scripted Bootstrap

Use `scripts/codex_lark_bootstrap.ps1` for repeatable local setup and diagnostics:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\KC\.codex\skills\codex-lark-bot\scripts\codex_lark_bootstrap.ps1 -Mode interactive
powershell -ExecutionPolicy Bypass -File C:\Users\KC\.codex\skills\codex-lark-bot\scripts\codex_lark_bootstrap.ps1 -Mode check -Agent both
powershell -ExecutionPolicy Bypass -File C:\Users\KC\.codex\skills\codex-lark-bot\scripts\codex_lark_bootstrap.ps1 -Mode install-cli -Agent both
powershell -ExecutionPolicy Bypass -File C:\Users\KC\.codex\skills\codex-lark-bot\scripts\codex_lark_bootstrap.ps1 -Mode new-app -Agent both -InstallIfMissing
powershell -ExecutionPolicy Bypass -File C:\Users\KC\.codex\skills\codex-lark-bot\scripts\codex_lark_bootstrap.ps1 -Mode existing-app -AppId <app_id> -Brand feishu -Agent claude -InstallIfMissing
powershell -ExecutionPolicy Bypass -File C:\Users\KC\.codex\skills\codex-lark-bot\scripts\codex_lark_bootstrap.ps1 -Mode doctor -Agent both
powershell -ExecutionPolicy Bypass -File C:\Users\KC\.codex\skills\codex-lark-bot\scripts\codex_lark_bootstrap.ps1 -Mode bridge -Agent claude
```

The script never accepts `app_secret` as a command-line argument. For `existing-app`, it prompts securely and passes the secret through stdin.

`-InstallIfMissing` installs `@larksuite/cli` with npm if `lark-cli` is absent. `-Agent claude` also runs `npx skills add larksuite/cli -g -y` so Claude Code receives the official Lark skills. `-Mode bridge` starts a long-running local listener; keep its terminal open.

## Local Bridge

The bridge is required for real Feishu/Lark-to-agent interaction. App creation alone only configures credentials.

```powershell
npx github:panjinggee-bit/codex-lark-bot bridge
```

Bridge behavior:

- Subscribes to `im.message.receive_v1` with `lark-cli event +subscribe --compact --quiet`.
- Handles text messages delivered to the bot and ignores empty, non-text, duplicate, and bot-sender messages.
- Invokes Claude Code with `claude --print --permission-mode plan`.
- Invokes Codex CLI with `codex exec -`.
- Replies through `lark-cli im +messages-reply --as bot`.
- Keeps a small in-memory de-duplication cache for recent `message_id` values.

The local machine must stay online while the bridge is running. If Feishu/Lark does not deliver messages, verify the app has bot capability, event subscription includes `im.message.receive_v1`, WebSocket event receiving is enabled, the app is published/installed, and the bridge terminal is still running.

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
