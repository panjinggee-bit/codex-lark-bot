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
- Run `lark-cli auth scopes --format pretty` after changing scopes.
- Run `lark-cli doctor` after changing app credentials or auth state.

## Useful validation commands

```powershell
lark-cli contact +search-user --query "<name-or-email>" --format table
lark-cli im +chat-create --name "Codex Bot Test" --users "<ou_xxx>" --type private --set-bot-manager --format pretty
lark-cli im +messages-send --chat-id "<oc_xxx>" --text "Codex bot connection OK"
```

## Failure interpretation

- Missing command: install or repair `lark-cli`.
- Invalid app credentials: re-run `config init` and pass the secret through stdin.
- Permission denied or missing scope: enable the reported scope in the app console, then publish or reinstall if required.
- Bot cannot send to user: verify the user open_id, app installation, bot visibility, and whether direct messages are allowed.
- Chat creation fails with bot identity: verify bot capability and IM chat scopes.
