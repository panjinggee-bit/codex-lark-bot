param(
  [ValidateSet("interactive", "check", "install-cli", "new-app", "existing-app", "doctor", "bridge", "install-service", "start-service", "stop-service", "status-service", "uninstall-service")]
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

function Test-LarkConfigReady {
  $raw = & lark-cli doctor --offline 2>&1
  try {
    $text = ($raw | Out-String)
    $json = $text | ConvertFrom-Json
    $app = $json.checks | Where-Object { $_.name -eq "app_resolved" } | Select-Object -First 1
    return ($app -and $app.status -eq "pass")
  }
  catch {
    return $false
  }
}

function Ensure-LarkConnection {
  if (Test-LarkConfigReady) {
    Write-Success "Found existing Feishu/Lark app configuration."
    return
  }

  Run-Step "Connect Feishu/Lark app/bot" {
    Create-NewApp
  }
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

function Get-ServiceTaskName {
  param([string]$BridgeAgent)
  return "CodexLarkBotBridge-$BridgeAgent"
}

function Get-MacServiceLabel {
  param([string]$BridgeAgent)
  return "com.panjinggee.codex-lark-bot.bridge.$BridgeAgent"
}

function Get-BridgeLogPath {
  param([string]$BridgeAgent)
  $skillRoot = Split-Path $PSScriptRoot -Parent
  $logDir = Join-Path $skillRoot "logs"
  if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
  }
  return (Join-Path $logDir "bridge-$BridgeAgent.log")
}

function Get-WindowsLauncherPath {
  param([string]$BridgeAgent)
  $skillRoot = Split-Path $PSScriptRoot -Parent
  $runDir = Join-Path $skillRoot "run"
  if (-not (Test-Path $runDir)) {
    New-Item -ItemType Directory -Path $runDir | Out-Null
  }
  return (Join-Path $runDir "bridge-$BridgeAgent.cmd")
}

function Get-WindowsRunValueName {
  param([string]$BridgeAgent)
  return "CodexLarkBotBridge-$BridgeAgent"
}

function Get-WindowsRunKeyPath {
  return "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
}

function Get-WindowsBridgeProcesses {
  param([string]$BridgeAgent)
  $agentNeedle = "-Agent $BridgeAgent"
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -and
      $_.CommandLine -like "*codex_lark_bootstrap.ps1*" -and
      $_.CommandLine -like "*-Mode bridge*" -and
      $_.CommandLine -like "*$agentNeedle*"
    }
}

function Stop-WindowsBridgeProcesses {
  param([string]$BridgeAgent)
  $processes = @(Get-WindowsBridgeProcesses -BridgeAgent $BridgeAgent)
  foreach ($process in $processes) {
    try {
      Invoke-CimMethod -InputObject $process -MethodName Terminate | Out-Null
      Write-Host "Stopped bridge process: $($process.ProcessId)"
    }
    catch {
      Write-Warning "Could not stop bridge process $($process.ProcessId): $($_.Exception.Message)"
    }
  }
}

function Test-IsWindows {
  return (($env:OS -eq "Windows_NT") -or ($PSVersionTable.Platform -eq "Win32NT"))
}

function Test-IsMacOS {
  return ($PSVersionTable.Platform -eq "Unix" -and (Get-Command "launchctl" -ErrorAction SilentlyContinue) -and (Test-Path "/System/Library/CoreServices/SystemVersion.plist"))
}

function ConvertTo-XmlText {
  param([string]$Text)
  return [System.Security.SecurityElement]::Escape($Text)
}

function Install-WindowsBridgeService {
  param([string]$BridgeAgent)
  Ensure-Command "Register-ScheduledTask"
  $taskName = Get-ServiceTaskName -BridgeAgent $BridgeAgent
  $logPath = Get-BridgeLogPath -BridgeAgent $BridgeAgent
  $bootstrapPath = Join-Path $PSScriptRoot "codex_lark_bootstrap.ps1"
  $launcherPath = Get-WindowsLauncherPath -BridgeAgent $BridgeAgent
  $launcher = @"
@echo off
set "PATH=$env:PATH"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$bootstrapPath" -Mode bridge -Agent $BridgeAgent >> "$logPath" 2>&1
"@
  [System.IO.File]::WriteAllText($launcherPath, $launcher, [System.Text.UTF8Encoding]::new($false))

  $action = New-ScheduledTaskAction -Execute $launcherPath
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

  try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Runs codex-lark-bot local bridge for $BridgeAgent at user logon." -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Success "Background bridge service installed and started: $taskName"
    Write-Host "Launcher: $launcherPath"
    Write-Host "Log file: $logPath"
  }
  catch {
    Write-Warning "Task Scheduler registration failed: $($_.Exception.Message)"
    Write-Warning "Falling back to the current user's Windows startup registry. This does not require administrator permission."
    Install-WindowsRunBridgeService -BridgeAgent $BridgeAgent -LauncherPath $launcherPath -LogPath $logPath
  }
}

function Install-WindowsRunBridgeService {
  param(
    [string]$BridgeAgent,
    [string]$LauncherPath,
    [string]$LogPath
  )

  $runKey = Get-WindowsRunKeyPath
  $valueName = Get-WindowsRunValueName -BridgeAgent $BridgeAgent
  if (-not (Test-Path $runKey)) {
    New-Item -Path $runKey -Force | Out-Null
  }

  Set-ItemProperty -Path $runKey -Name $valueName -Value "`"$LauncherPath`""
  Start-Process -FilePath $LauncherPath -WindowStyle Hidden
  Write-Success "Background bridge startup entry installed and started: $valueName"
  Write-Host "Startup entry: $runKey\$valueName"
  Write-Host "Launcher: $LauncherPath"
  Write-Host "Log file: $LogPath"
}

function Install-MacBridgeService {
  param([string]$BridgeAgent)
  Ensure-Command "launchctl"
  Ensure-Command "pwsh"

  $label = Get-MacServiceLabel -BridgeAgent $BridgeAgent
  $launchAgentsDir = Join-Path $HOME "Library/LaunchAgents"
  if (-not (Test-Path $launchAgentsDir)) {
    New-Item -ItemType Directory -Path $launchAgentsDir | Out-Null
  }

  $plistPath = Join-Path $launchAgentsDir "$label.plist"
  $logPath = Get-BridgeLogPath -BridgeAgent $BridgeAgent
  $bootstrapPath = Join-Path $PSScriptRoot "codex_lark_bootstrap.ps1"
  $domain = "gui/$(id -u)"
  $envPath = if ($env:PATH) { $env:PATH } else { "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" }

  $plist = @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(ConvertTo-XmlText $label)</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/env</string>
    <string>pwsh</string>
    <string>-NoProfile</string>
    <string>-ExecutionPolicy</string>
    <string>Bypass</string>
    <string>-File</string>
    <string>$(ConvertTo-XmlText $bootstrapPath)</string>
    <string>-Mode</string>
    <string>bridge</string>
    <string>-Agent</string>
    <string>$(ConvertTo-XmlText $BridgeAgent)</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$(ConvertTo-XmlText $logPath)</string>
  <key>StandardErrorPath</key>
  <string>$(ConvertTo-XmlText $logPath)</string>
  <key>WorkingDirectory</key>
  <string>$(ConvertTo-XmlText $HOME)</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$(ConvertTo-XmlText $envPath)</string>
  </dict>
</dict>
</plist>
"@

  [System.IO.File]::WriteAllText($plistPath, $plist, [System.Text.UTF8Encoding]::new($false))
  & launchctl bootout $domain $plistPath 2>$null
  & launchctl bootstrap $domain $plistPath
  if ($LASTEXITCODE -ne 0) {
    throw "launchctl bootstrap failed for $plistPath"
  }
  & launchctl kickstart -k "$domain/$label"
  Write-Success "Background bridge LaunchAgent installed and started: $label"
  Write-Host "Plist: $plistPath"
  Write-Host "Log file: $logPath"
}

function Install-BridgeService {
  $bridgeAgent = Resolve-BridgeAgent
  $script:Agent = $bridgeAgent
  $script:InstallIfMissing = $true
  Ensure-AgentTools
  Ensure-LarkConnection

  Run-Step "Install background bridge service" {
    if (Test-IsWindows) {
      Install-WindowsBridgeService -BridgeAgent $bridgeAgent
    }
    elseif (Test-IsMacOS) {
      Install-MacBridgeService -BridgeAgent $bridgeAgent
    }
    else {
      throw "Background service install currently supports Windows and macOS only."
    }
  }
}

function Start-BridgeService {
  $bridgeAgent = Resolve-BridgeAgent
  Run-Step "Start background bridge service" {
    if (Test-IsWindows) {
      $taskName = Get-ServiceTaskName -BridgeAgent $bridgeAgent
      $launcherPath = Get-WindowsLauncherPath -BridgeAgent $bridgeAgent
      $runValueName = Get-WindowsRunValueName -BridgeAgent $bridgeAgent
      $runEntry = Get-ItemProperty -Path (Get-WindowsRunKeyPath) -Name $runValueName -ErrorAction SilentlyContinue
      if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Start-ScheduledTask -TaskName $taskName
      }
      elseif ($runEntry -and (Test-Path $launcherPath)) {
        Start-Process -FilePath $launcherPath -WindowStyle Hidden
      }
      else {
        throw "No Windows background bridge service found for $bridgeAgent. Run install-service first."
      }
    }
    elseif (Test-IsMacOS) {
      $label = Get-MacServiceLabel -BridgeAgent $bridgeAgent
      $plistPath = Join-Path (Join-Path $HOME "Library/LaunchAgents") "$label.plist"
      & launchctl bootstrap "gui/$(id -u)" $plistPath 2>$null
      & launchctl kickstart -k "gui/$(id -u)/$label"
    }
    else {
      throw "Background service management currently supports Windows and macOS only."
    }
    Write-Success "Started background bridge service for $bridgeAgent"
  }
}

function Stop-BridgeService {
  $bridgeAgent = Resolve-BridgeAgent
  Run-Step "Stop background bridge service" {
    if (Test-IsWindows) {
      $taskName = Get-ServiceTaskName -BridgeAgent $bridgeAgent
      if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $taskName
      }
      Stop-WindowsBridgeProcesses -BridgeAgent $bridgeAgent
    }
    elseif (Test-IsMacOS) {
      $label = Get-MacServiceLabel -BridgeAgent $bridgeAgent
      $plistPath = Join-Path (Join-Path $HOME "Library/LaunchAgents") "$label.plist"
      & launchctl bootout "gui/$(id -u)" $plistPath
    }
    else {
      throw "Background service management currently supports Windows and macOS only."
    }
    Write-Success "Stopped background bridge service for $bridgeAgent"
  }
}

function Show-BridgeServiceStatus {
  $bridgeAgent = Resolve-BridgeAgent
  Run-Step "Background bridge service status" {
    if (Test-IsWindows) {
      $taskName = Get-ServiceTaskName -BridgeAgent $bridgeAgent
      $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
      if ($task) {
        $info = Get-ScheduledTaskInfo -TaskName $taskName
        Write-Host "Mode: Task Scheduler"
        Write-Host "Task: $taskName"
        Write-Host "State: $($task.State)"
        Write-Host "Last run: $($info.LastRunTime)"
        Write-Host "Last result: $($info.LastTaskResult)"
        Write-Host "Next run: $($info.NextRunTime)"
      }
      else {
        $runValueName = Get-WindowsRunValueName -BridgeAgent $bridgeAgent
        $runEntry = Get-ItemProperty -Path (Get-WindowsRunKeyPath) -Name $runValueName -ErrorAction SilentlyContinue
        Write-Host "Mode: Windows current-user startup registry"
        if ($runEntry) {
          Write-Host "Startup entry: $runValueName"
          Write-Host "Command: $($runEntry.$runValueName)"
        }
        else {
          Write-Warning "No startup entry found for $bridgeAgent."
        }
      }
      $processes = @(Get-WindowsBridgeProcesses -BridgeAgent $bridgeAgent)
      if ($processes.Count -gt 0) {
        Write-Host "Running process IDs: $($processes.ProcessId -join ', ')"
      }
      else {
        Write-Host "Running process IDs: <none>"
      }
    }
    elseif (Test-IsMacOS) {
      $label = Get-MacServiceLabel -BridgeAgent $bridgeAgent
      Write-Host "LaunchAgent: $label"
      & launchctl print "gui/$(id -u)/$label"
    }
    else {
      throw "Background service management currently supports Windows and macOS only."
    }
    Write-Host "Log file: $(Get-BridgeLogPath -BridgeAgent $bridgeAgent)"
  }
}

function Uninstall-BridgeService {
  $bridgeAgent = Resolve-BridgeAgent
  Run-Step "Uninstall background bridge service" {
    if (Test-IsWindows) {
      $taskName = Get-ServiceTaskName -BridgeAgent $bridgeAgent
      Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
      Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
      Stop-WindowsBridgeProcesses -BridgeAgent $bridgeAgent
      Remove-ItemProperty -Path (Get-WindowsRunKeyPath) -Name (Get-WindowsRunValueName -BridgeAgent $bridgeAgent) -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath (Get-WindowsLauncherPath -BridgeAgent $bridgeAgent) -ErrorAction SilentlyContinue
    }
    elseif (Test-IsMacOS) {
      $label = Get-MacServiceLabel -BridgeAgent $bridgeAgent
      $plistPath = Join-Path (Join-Path $HOME "Library/LaunchAgents") "$label.plist"
      & launchctl bootout "gui/$(id -u)" $plistPath 2>$null
      Remove-Item -LiteralPath $plistPath -ErrorAction SilentlyContinue
    }
    else {
      throw "Background service management currently supports Windows and macOS only."
    }
    Write-Success "Uninstalled background bridge service for $bridgeAgent"
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

    Ensure-LarkConnection

    Run-Step "Verify connection" {
      Run-DoctorSummary
    }

    Install-BridgeService
  }

  "bridge" {
    if ($Agent -eq "both") {
      $script:Agent = Resolve-AgentInteractively
    }
    $script:InstallIfMissing = $true
    Ensure-AgentTools
    Ensure-LarkConnection
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

  "install-service" {
    Install-BridgeService
  }

  "start-service" {
    Start-BridgeService
  }

  "stop-service" {
    Stop-BridgeService
  }

  "status-service" {
    Show-BridgeServiceStatus
  }

  "uninstall-service" {
    Uninstall-BridgeService
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
