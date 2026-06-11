# Feishu/Lark Bot Setup Checklist

Use this checklist when `lark-cli` setup is incomplete or a bot command fails.

## Local prerequisites

- `node` and `npm` exist on PATH.
- `lark-cli` exists on PATH, or install it with `npm install -g @larksuite/cli`.
- For Codex CLI integration, `codex` exists on PATH.
- For Claude Code integration, `claude` exists on PATH and `npx skills add larksuite/cli -g -y` has been run.
- `lark-cli doctor --offline` can read local config.
- The configured brand matches the tenant: `feishu` for China Feishu, `lark` for global Lark.

## App creation paths

- Missing CLI: run `npm install -g @larksuite/cli`.
- New app: run `lark-cli config init --new --brand feishu --lang zh`.
- Existing app: run `lark-cli config init --brand feishu --app-id <app_id> --app-secret-stdin`.
- If the CLI prints a verification URL, open it and complete the Open Platform flow.
- If admin approval, publishing, app installation, or tenant selection is requested, pause and ask the user to complete that step.

## Bot capability checks

- Confirm the app has bot capability enabled in the Open Platform console.
- Confirm the app is installed in the target tenant.
- Confirm required scopes are enabled and published.
- Confirm event subscription uses WebSocket/long connection and includes `im.message.receive_v1`.
- Run `lark-cli auth scopes --format pretty` after changing scopes.
- Run `lark-cli doctor` after changing app credentials or auth state.

## Useful validation commands

```powershell
lark-cli contact +search-user --query "<name-or-email>" --format table
lark-cli im +chat-create --name "Codex Bot Test" --users "<ou_xxx>" --type private --set-bot-manager --format pretty
lark-cli im +messages-send --chat-id "<oc_xxx>" --text "Codex bot connection OK"
powershell -ExecutionPolicy Bypass -File "$HOME\.codex\skills\codex-lark-bot\scripts\codex_lark_bootstrap.ps1" -Mode bridge -Agent claude
```

## Failure interpretation

- Missing command: install or repair `lark-cli`.
- Invalid app credentials: re-run `config init` and pass the secret through stdin.
- Permission denied or missing scope: enable the reported scope in the app console, then publish or reinstall if required.
- Bot cannot send to user: verify the user open_id, app installation, bot visibility, and whether direct messages are allowed.
- Chat creation fails with bot identity: verify bot capability and IM chat scopes.
- Bot is created but does not call Claude/Codex: start the local bridge and keep the terminal open.
- Bridge receives no events: verify WebSocket event subscription, `im.message.receive_v1`, app publishing, app installation, and that the user is messaging or mentioning the bot.
- Bridge receives events but cannot reply: verify bot message reply scopes and run `lark-cli im +messages-reply --dry-run --message-id om_test --text test`.
