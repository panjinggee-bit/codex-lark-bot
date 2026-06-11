param(
  [ValidateSet("interactive", "check", "install-cli", "new-app", "existing-app", "doctor", "bridge")]
  [string]$Mode = "interactive",
  [ValidateSet("codex", "claude", "both")]
  [string]$Agent = "both",
  [ValidateSet("feishu", "lark")]
  [string]$Brand = "feishu",
  [string]$AppId = "",
  [switch]$InstallIfMissing
)

$ErrorActionPreference = "Stop"

function Run-Step {
  param(
    [string]$Label,
    [scriptblock]$Block
  )

  Write-Host ""
  Write-Host "== $Label =="
  & $Block
}

function Write-Success {
  param([string]$Message)
  Write-Host ""
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Mask-Value {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return "<empty>"
  }
  if ($Value.Length -le 8) {
    return ("*" * $Value.Length)
  }
  return "$($Value.Substring(0, 4))****$($Value.Substring($Value.Length - 4))"
}

function Find-Command {
  param([string]$Name)
  Get-Command $Name -ErrorAction SilentlyContinue
}

function Ensure-Command {
  param([string]$Name)
  $cmd = Find-Command $Name
  if (-not $cmd) {
    throw "$Name was not found on PATH."
  }
  Write-Host "${Name}: $($cmd.Source)"
}

function Ensure-LarkCli {
  $cmd = Find-Command "lark-cli"
  if ($cmd) {
    Write-Host "lark-cli: $($cmd.Source)"
    return
  }

  if (-not $InstallIfMissing -and $Mode -ne "install-cli") {
    throw "lark-cli was not found. Re-run with -InstallIfMissing, use -Mode install-cli, or choose automatic install in interactive mode."
  }

  Ensure-Command "npm"
  Write-Host "Installing @larksuite/cli globally with npm..."
  npm install -g @larksuite/cli
  Ensure-Command "lark-cli"
}

function Read-MenuChoice {
  param(
    [string]$Prompt,
    [string[]]$Options
  )

  Write-Host ""
  Write-Host $Prompt
  for ($i = 0; $i -lt $Options.Count; $i++) {
    Write-Host "  $($i + 1). $($Options[$i])"
  }

  while ($true) {
    $raw = Read-Host "Enter choice"
    $index = 0
    if ([int]::TryParse($raw, [ref]$index) -and $index -ge 1 -and $index -le $Options.Count) {
      return $index
    }
    Write-Warning "Please enter a number from 1 to $($Options.Count)."
  }
}

function Resolve-AgentInteractively {
  $choice = Read-MenuChoice "Which agent do you want to connect to Feishu/Lark?" @(
    "Claude Code",
    "Codex CLI"
  )

  switch ($choice) {
    1 { return "claude" }
    2 { return "codex" }
  }
}

function Resolve-BridgeAgent {
  if ($Agent -eq "claude" -or $Agent -eq "codex") {
    return $Agent
  }

  $choice = Read-MenuChoice "Which local agent should answer Feishu/Lark messages?" @(
    "Claude Code",
    "Codex CLI"
  )

  switch ($choice) {
    1 { return "claude" }
    2 { return "codex" }
  }
}

function Read-YesNo {
  param(
    [string]$Prompt,
    [bool]$DefaultYes = $true
  )

  $suffix = if ($DefaultYes) { "Y/n" } else { "y/N" }
  while ($true) {
    $answer = Read-Host "$Prompt [$suffix]"
    if ([string]::IsNullOrWhiteSpace($answer)) {
      return $DefaultYes
    }
    switch ($answer.Trim().ToLowerInvariant()) {
      "y" { return $true }
      "yes" { return $true }
      "n" { return $false }
      "no" { return $false }
      default { Write-Warning "Please answer y or n." }
    }
  }
}

function Ensure-AgentTools {
  Run-Step "Local commands" {
    Ensure-Command "node"
    Ensure-Command "npm"
    if ($Agent -eq "codex" -or $Agent -eq "both") {
      Ensure-Agent "codex"
    }
    if ($Agent -eq "claude" -or $Agent -eq "both") {
      Ensure-Agent "claude"
    }
    Ensure-LarkCli
  }
}

function Ensure-Agent {
  param([string]$Name)
  switch ($Name) {
    "codex" {
      $cmd = Find-Command "codex"
      if ($cmd) {
        Write-Host "codex: $($cmd.Source)"
      }
      else {
        Write-Warning "codex was not found on PATH. Feishu bot setup can continue, but Codex CLI invocation will not be verified."
      }
    }
    "claude" {
      $cmd = Find-Command "claude"
      if ($cmd) {
        Write-Host "claude: $($cmd.Source)"
      }
      else {
        Write-Warning "claude was not found on PATH. Feishu bot setup can continue, but Claude Code invocation will not be verified."
      }
    }
  }
}

function Ensure-ClaudeLarkSkills {
  if ($Agent -ne "claude" -and $Agent -ne "both") {
    return
  }

  Ensure-Command "npx"
  Write-Host "Installing Lark CLI skills for Claude Code..."
  npx skills add larksuite/cli -g -y
}

function Configure-ExistingApp {
  if ([string]::IsNullOrWhiteSpace($AppId)) {
    $script:AppId = Read-Host "Enter Feishu/Lark App ID"
  }

  if ([string]::IsNullOrWhiteSpace($AppId)) {
    throw "App ID is required."
  }

  Write-Host "App ID: $(Mask-Value $AppId)"
  Write-Host "App Secret: <hidden>"

  $secret = Read-Host "Enter Feishu/Lark App Secret" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
  try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    if ([string]::IsNullOrWhiteSpace($plain)) {
      throw "App Secret is required."
    }
    $plain | lark-cli config init --brand $Brand --app-id $AppId --app-secret-stdin
  }
  finally {
    if ($bstr -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
  }
}

function Create-NewApp {
  Write-Host "Feishu/Lark may open a browser, show a verification URL, or show a QR code."
  Write-Host "Scan or confirm the prompt, then choose an existing app/bot or create a new one in the official Feishu/Lark flow."
  lark-cli config init --new --brand $Brand --lang zh
}

function Run-DoctorSummary {
  $raw = & lark-cli doctor 2>&1
  $raw | ForEach-Object { Write-Host $_ }

  try {
    $text = ($raw | Out-String)
    $json = $text | ConvertFrom-Json
    $app = $json.checks | Where-Object { $_.name -eq "app_resolved" } | Select-Object -First 1
    if ($json.ok -or ($app -and $app.status -eq "pass")) {
      Write-Success "Feishu/Lark bot connection succeeded. Your local agent can now use lark-cli with this bot app."
      return
    }
  }
  catch {
    Write-Warning "Could not parse lark-cli doctor output; review the messages above."
  }

  Write-Warning "Connection is not fully healthy yet. Review the doctor output above, then rerun this script with -Mode doctor."
}

function Start-LocalBridge {
  $bridgeAgent = Resolve-BridgeAgent
  $bridgeScript = Join-Path $PSScriptRoot "lark_agent_bridge.ps1"
  if (-not (Test-Path $bridgeScript)) {
    throw "Bridge script not found: $bridgeScript"
  }

  Run-Step "Start local Feishu/Lark bridge" {
    Write-Host "The bridge keeps this terminal open and listens for Feishu/Lark messages."
    Write-Host "Press Ctrl+C to stop it."
    & powershell -ExecutionPolicy Bypass -File $bridgeScript -Agent $bridgeAgent
  }
}

function Try-Native {
  param(
    [string]$Label,
    [scriptblock]$Block
  )

  try {
    & $Block
  }
  catch {
    Write-Warning "$Label failed: $($_.Exception.Message)"
  }
}

switch ($Mode) {
  "interactive" {
    $script:Agent = Resolve-AgentInteractively
    $script:InstallIfMissing = $true

    Ensure-AgentTools

    Run-Step "Install Claude Code Lark skills when requested" {
      Ensure-ClaudeLarkSkills
    }

    Run-Step "Connect Feishu/Lark app/bot" {
      Create-NewApp
    }

    Run-Step "Verify connection" {
      Run-DoctorSummary
    }

    if (Read-YesNo -Prompt "Start local bridge now?" -DefaultYes $true) {
      Start-LocalBridge
    }
  }

  "bridge" {
    Ensure-AgentTools
    Start-LocalBridge
  }

  "install-cli" {
    Ensure-AgentTools
    Run-Step "Install or verify lark-cli" {
      Ensure-LarkCli
      lark-cli --version
    }
    Run-Step "Install Claude Code Lark skills when requested" {
      Ensure-ClaudeLarkSkills
    }
  }

  "check" {
    Ensure-AgentTools
    Run-Step "Versions" {
      if ($Agent -eq "codex" -or $Agent -eq "both") {
        Try-Native "codex --version" { codex --version }
      }
      if ($Agent -eq "claude" -or $Agent -eq "both") {
        Try-Native "claude --version" { claude --version }
      }
      Try-Native "lark-cli --version" { lark-cli --version }
    }
    Run-Step "Offline doctor" {
      lark-cli doctor --offline
    }
  }

  "new-app" {
    Ensure-AgentTools
    Run-Step "Install Claude Code Lark skills when requested" {
      Ensure-ClaudeLarkSkills
    }
    Run-Step "Create new Feishu/Lark app through lark-cli" {
      Write-Host "This may open or print a browser verification URL. Complete the Open Platform prompts when requested."
      lark-cli config init --new --brand $Brand --lang zh
    }
    Run-Step "Doctor" {
      lark-cli doctor
    }
  }

  "existing-app" {
    Ensure-AgentTools

    Run-Step "Configure existing app" {
      Configure-ExistingApp
    }
    Run-Step "Install Claude Code Lark skills when requested" {
      Ensure-ClaudeLarkSkills
    }
    Run-Step "Doctor" {
      lark-cli doctor
    }
  }

  "doctor" {
    Ensure-AgentTools
    Run-Step "Configuration" {
      lark-cli config show
    }
    Run-Step "Auth status" {
      lark-cli auth status
    }
    Run-Step "Enabled scopes" {
      lark-cli auth scopes --format pretty
    }
    Run-Step "Doctor" {
      lark-cli doctor
    }
  }
}
