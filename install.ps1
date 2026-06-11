$ErrorActionPreference = "Stop"

$repo = "https://github.com/panjinggee-bit/codex-lark-bot.git"
$skillRoot = Join-Path $HOME ".codex\skills"
$skillDir = Join-Path $skillRoot "codex-lark-bot"

function Ensure-Command {
  param(
    [string]$Name,
    [string]$InstallHint
  )

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name was not found. $InstallHint"
  }
}

Ensure-Command "git" "Install Git first, then rerun this command."

if (-not (Test-Path $skillRoot)) {
  New-Item -ItemType Directory -Path $skillRoot | Out-Null
}

if (Test-Path $skillDir) {
  Write-Host "Updating existing skill at $skillDir"
  git -C $skillDir pull --ff-only
}
else {
  Write-Host "Installing codex-lark-bot skill to $skillDir"
  git clone $repo $skillDir
}

$bootstrap = Join-Path $skillDir "scripts\codex_lark_bootstrap.ps1"
Write-Host ""
Write-Host "Starting Feishu/Lark agent connection wizard..."
& powershell -ExecutionPolicy Bypass -File $bootstrap -Mode interactive
