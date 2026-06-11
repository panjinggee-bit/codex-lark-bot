param(
  [ValidateSet("check", "install-cli", "new-app", "existing-app", "doctor")]
  [string]$Mode = "check",
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

function Require-Command {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "$Name was not found on PATH."
  }
  Write-Host "${Name}: $($cmd.Source)"
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
    throw "lark-cli was not found. Re-run with -InstallIfMissing or use -Mode install-cli."
  }

  Ensure-Command "npm"
  Write-Host "Installing @larksuite/cli globally with npm..."
  npm install -g @larksuite/cli
  Ensure-Command "lark-cli"
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

switch ($Mode) {
  "install-cli" {
    Run-Step "Install or verify lark-cli" {
      Ensure-LarkCli
      lark-cli --version
    }
    Run-Step "Install Claude Code Lark skills when requested" {
      Ensure-ClaudeLarkSkills
    }
  }

  "check" {
    Run-Step "Versions" {
      Try-Native "codex --version" { codex --version }
      Try-Native "claude --version" { claude --version }
      Try-Native "lark-cli --version" { lark-cli --version }
    }
    Run-Step "Offline doctor" {
      lark-cli doctor --offline
    }
  }

  "new-app" {
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
    if ([string]::IsNullOrWhiteSpace($AppId)) {
      throw "-AppId is required for -Mode existing-app."
    }

    Run-Step "Configure existing app" {
      $secret = Read-Host "App Secret" -AsSecureString
      $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
      try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        $plain | lark-cli config init --brand $Brand --app-id $AppId --app-secret-stdin
      }
      finally {
        if ($bstr -ne [IntPtr]::Zero) {
          [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
      }
    }
    Run-Step "Install Claude Code Lark skills when requested" {
      Ensure-ClaudeLarkSkills
    }
    Run-Step "Doctor" {
      lark-cli doctor
    }
  }

  "doctor" {
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
