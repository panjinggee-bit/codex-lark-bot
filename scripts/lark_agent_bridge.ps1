param(
  [ValidateSet("claude", "codex")]
  [string]$Agent = "claude",
  [int]$MaxReplyChars = 3500
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$systemContext = @"
You are replying to a Feishu/Lark user message through a local bridge.
Keep the reply concise and useful.
Do not modify local files or run risky actions from this bridge response.
If the user asks for a risky local action, ask them to confirm in their local agent session instead.
"@

$seenMessages = [System.Collections.Generic.Queue[string]]::new()
$seenSet = [System.Collections.Generic.HashSet[string]]::new()

function Write-Info {
  param([string]$Message)
  Write-Host "[bridge] $Message"
}

function Write-BridgeError {
  param([string]$Message)
  Write-Host "[bridge:error] $Message" -ForegroundColor Red
}

function Find-CommandOrThrow {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "$Name was not found on PATH."
  }
  return $cmd.Source
}

function Add-SeenMessage {
  param([string]$MessageId)
  if ([string]::IsNullOrWhiteSpace($MessageId)) {
    return $false
  }
  if ($seenSet.Contains($MessageId)) {
    return $false
  }
  [void]$seenSet.Add($MessageId)
  $seenMessages.Enqueue($MessageId)
  while ($seenMessages.Count -gt 200) {
    $old = $seenMessages.Dequeue()
    [void]$seenSet.Remove($old)
  }
  return $true
}

function Get-FirstValueByName {
  param(
    [object]$Node,
    [string[]]$Names
  )

  if ($null -eq $Node) {
    return $null
  }

  if ($Node -is [System.Collections.IDictionary]) {
    foreach ($name in $Names) {
      if ($Node.Contains($name) -and $null -ne $Node[$name]) {
        return $Node[$name]
      }
    }
    foreach ($key in $Node.Keys) {
      $value = Get-FirstValueByName -Node $Node[$key] -Names $Names
      if ($null -ne $value) {
        return $value
      }
    }
    return $null
  }

  if ($Node -is [System.Array]) {
    foreach ($item in $Node) {
      $value = Get-FirstValueByName -Node $item -Names $Names
      if ($null -ne $value) {
        return $value
      }
    }
    return $null
  }

  if ($Node -is [string] -or $Node.GetType().IsValueType) {
    return $null
  }

  if ($Node.PSObject -and $Node.PSObject.Properties) {
    foreach ($name in $Names) {
      $property = $Node.PSObject.Properties[$name]
      if ($property -and $null -ne $property.Value) {
        return $property.Value
      }
    }
    foreach ($property in $Node.PSObject.Properties) {
      $value = Get-FirstValueByName -Node $property.Value -Names $Names
      if ($null -ne $value) {
        return $value
      }
    }
  }

  return $null
}

function Convert-MessageText {
  param([object]$Raw)

  if ($null -eq $Raw) {
    return ""
  }

  $text = [string]$Raw
  if ([string]::IsNullOrWhiteSpace($text)) {
    return ""
  }

  $trimmed = $text.Trim()
  if ($trimmed.StartsWith("{")) {
    try {
      $content = $trimmed | ConvertFrom-Json
      $nestedText = Get-FirstValueByName -Node $content -Names @("text", "content")
      if ($null -ne $nestedText) {
        return ([string]$nestedText).Trim()
      }
    }
    catch {
      return $trimmed
    }
  }

  return $trimmed
}

function Get-EventMessage {
  param([object]$Event)

  $messageId = Get-FirstValueByName -Node $Event -Names @("message_id", "messageId")
  $rawText = Get-FirstValueByName -Node $Event -Names @("text", "content")
  $chatType = Get-FirstValueByName -Node $Event -Names @("chat_type", "chatType")
  $senderType = Get-FirstValueByName -Node $Event -Names @("sender_type", "senderType")
  $messageType = Get-FirstValueByName -Node $Event -Names @("message_type", "messageType", "msg_type", "msgType")

  $text = Convert-MessageText -Raw $rawText

  [pscustomobject]@{
    MessageId = [string]$messageId
    Text = $text
    ChatType = [string]$chatType
    SenderType = [string]$senderType
    MessageType = [string]$messageType
  }
}

function Get-EventMessageFromCompactLine {
  param([string]$Line)

  $messageId = ""
  $content = ""
  $chatType = ""
  $senderType = ""
  $messageType = ""

  if ($Line -match '"message_id":"([^"]+)"') {
    $messageId = $Matches[1]
  }
  elseif ($Line -match '"id":"([^"]+)"') {
    $messageId = $Matches[1]
  }

  if ($Line -match '"content":"(.*?)","create_time"') {
    $content = $Matches[1]
  }
  elseif ($Line -match '"text":"(.*?)"') {
    $content = $Matches[1]
  }

  if ($Line -match '"chat_type":"([^"]+)"') {
    $chatType = $Matches[1]
  }
  if ($Line -match '"sender_type":"([^"]+)"') {
    $senderType = $Matches[1]
  }
  if ($Line -match '"message_type":"([^"]+)"') {
    $messageType = $Matches[1]
  }

  [pscustomobject]@{
    MessageId = $messageId
    Text = (Convert-MessageText -Raw $content)
    ChatType = $chatType
    SenderType = $senderType
    MessageType = $messageType
  }
}

function Test-ShouldHandleMessage {
  param([object]$Message)

  if ([string]::IsNullOrWhiteSpace($Message.MessageId) -or [string]::IsNullOrWhiteSpace($Message.Text)) {
    return $false
  }

  if ($Message.SenderType -match "bot") {
    return $false
  }

  if ($Message.MessageType -and $Message.MessageType -notmatch "text|post") {
    return $false
  }

  return $true
}

function Truncate-Text {
  param(
    [string]$Text,
    [int]$Limit
  )

  if ($Text.Length -le $Limit) {
    return $Text
  }

  return $Text.Substring(0, $Limit) + "`n`n[reply truncated; ask the bot to continue]"
}

function Invoke-ClaudeAgent {
  param([string]$UserText)

  $prompt = "$systemContext`n`nUser message:`n$UserText"
  $output = & claude --print --permission-mode plan $prompt 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "claude failed with exit code $LASTEXITCODE`: $($output | Out-String)"
  }
  return (($output | Out-String).Trim())
}

function Invoke-CodexAgent {
  param([string]$UserText)

  $prompt = "$systemContext`n`nUser message:`n$UserText"
  $promptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-lark-prompt-" + [guid]::NewGuid().ToString("N") + ".txt")
  [System.IO.File]::WriteAllText($promptPath, $prompt, [System.Text.UTF8Encoding]::new($false))

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $powerShellExe = if (Get-Command "pwsh" -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
  $escapedPromptPath = $promptPath.Replace("'", "''")
  $psi.FileName = $powerShellExe
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"Get-Content -Raw -Encoding UTF8 -LiteralPath '$escapedPromptPath' | codex exec --skip-git-repo-check -`""
  $psi.WorkingDirectory = [Environment]::GetFolderPath("UserProfile")
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false

  try {
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
      throw "codex failed with exit code $($process.ExitCode): $stderr"
    }

    return $stdout.Trim()
  }
  finally {
    Remove-Item -LiteralPath $promptPath -ErrorAction SilentlyContinue
  }
}

function Invoke-Agent {
  param([string]$UserText)

  switch ($Agent) {
    "claude" { return Invoke-ClaudeAgent -UserText $UserText }
    "codex" { return Invoke-CodexAgent -UserText $UserText }
  }
}

function Reply-ToMessage {
  param(
    [string]$MessageId,
    [string]$ReplyText
  )

  $safeReply = Truncate-Text -Text $ReplyText -Limit $MaxReplyChars
  & lark-cli im +messages-reply --as bot --message-id $MessageId --text $safeReply
  if ($LASTEXITCODE -ne 0) {
    throw "lark-cli reply failed with exit code $LASTEXITCODE"
  }
}

Find-CommandOrThrow "lark-cli" | Out-Null
Find-CommandOrThrow $Agent | Out-Null
Find-CommandOrThrow "node" | Out-Null

$nodeBridge = Join-Path $PSScriptRoot "lark_agent_bridge.js"
if (Test-Path $nodeBridge) {
  & node $nodeBridge --agent $Agent --max-reply-chars $MaxReplyChars
  exit $LASTEXITCODE
}

Write-Info "Starting local Feishu/Lark bridge with agent: $Agent"
Write-Info "Only text events from im.message.receive_v1 are handled. Press Ctrl+C to stop."

$powerShellExe = if (Get-Command "pwsh" -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
$subscriberCommand = "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(`$false); `$OutputEncoding = [System.Text.UTF8Encoding]::new(`$false); lark-cli event +subscribe --event-types im.message.receive_v1 --compact --quiet"
$subscriber = [System.Diagnostics.ProcessStartInfo]::new()
$subscriber.FileName = $powerShellExe
$escapedSubscriberCommand = $subscriberCommand.Replace('"', '\"')
$subscriber.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$escapedSubscriberCommand`""
$subscriber.RedirectStandardOutput = $true
$subscriber.RedirectStandardError = $true
$subscriber.UseShellExecute = $false

$eventProcess = [System.Diagnostics.Process]::Start($subscriber)
Write-Info "Listening for Feishu/Lark messages..."

while (-not $eventProcess.HasExited) {
  $line = $eventProcess.StandardOutput.ReadLine()
  if ($null -eq $line) {
    Start-Sleep -Milliseconds 100
    continue
  }
  if ([string]::IsNullOrWhiteSpace($line)) {
    continue
  }

  try {
    try {
      $event = $line | ConvertFrom-Json
      $message = Get-EventMessage -Event $event
    }
    catch {
      Write-BridgeError "Could not parse compact JSON; falling back to tolerant parser. $($_.Exception.Message)"
      $message = Get-EventMessageFromCompactLine -Line $line
    }

    if (-not (Test-ShouldHandleMessage -Message $message)) {
      continue
    }

    if (-not (Add-SeenMessage -MessageId $message.MessageId)) {
      continue
    }

    Write-Info "Received message $($message.MessageId): $($message.Text)"
    try {
      $reply = Invoke-Agent -UserText $message.Text
      if ([string]::IsNullOrWhiteSpace($reply)) {
        $reply = "Agent returned an empty response."
      }
    }
    catch {
      $agentError = $_.Exception.Message
      Write-BridgeError $agentError
      $reply = "Local $Agent failed to answer. Check the bridge terminal for details: $agentError"
    }
    Reply-ToMessage -MessageId $message.MessageId -ReplyText $reply
    Write-Info "Replied to $($message.MessageId)"
  }
  catch {
    Write-BridgeError $_.Exception.Message
  }
}

$stderrText = $eventProcess.StandardError.ReadToEnd()
if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
  Write-BridgeError $stderrText
}

exit $eventProcess.ExitCode
