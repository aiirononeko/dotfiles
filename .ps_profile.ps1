Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Add-ToPath {
  param([Parameter(Mandatory = $true)][string]$PathValue)

  if (-not (Test-Path -LiteralPath $PathValue)) {
    return
  }

  $current = @($env:PATH -split ";" | Where-Object { $_ -ne "" })
  if ($current -notcontains $PathValue) {
    $env:PATH = "$PathValue;$env:PATH"
  }
}

$localBin = Join-Path $HOME ".local\bin"
Add-ToPath -PathValue $localBin

if ($env:LOCALAPPDATA) {
  $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
  Add-ToPath -PathValue $wingetLinks
}

$env:EDITOR = "nvim"

if (Get-Command "mise" -ErrorAction SilentlyContinue) {
  $miseHook = & mise activate pwsh 2>$null
  if (-not $miseHook) {
    $miseHook = & mise activate powershell 2>$null
  }
  if ($miseHook) {
    Invoke-Expression ($miseHook | Out-String)
  }
}

if (Get-Command "direnv" -ErrorAction SilentlyContinue) {
  Invoke-Expression (& direnv hook pwsh | Out-String)
}

$bunDir = Join-Path $HOME ".bun"
if (Test-Path -LiteralPath $bunDir) {
  $env:BUN_INSTALL = $bunDir
  Add-ToPath -PathValue (Join-Path $bunDir "bin")

  if (Get-Command "bun" -ErrorAction SilentlyContinue) {
    try {
      Invoke-Expression (& bun completions powershell | Out-String)
    } catch {
      # Ignore completion setup failures to keep shell startup resilient.
    }
  }
}

function repo {
  if (-not (Get-Command "ghq" -ErrorAction SilentlyContinue)) {
    Write-Warning "ghq is required."
    return
  }
  if (-not (Get-Command "fzf" -ErrorAction SilentlyContinue)) {
    Write-Warning "fzf is required."
    return
  }

  $root = (& ghq root).Trim()
  $selected = (& ghq list | & fzf --reverse --height=50%)
  if ($selected) {
    Set-Location (Join-Path $root $selected.Trim())
  }
}

if (Get-Module -ListAvailable -Name PSReadLine) {
  Set-PSReadLineKeyHandler -Chord Ctrl+g -BriefDescription "ghq repo chooser" -ScriptBlock {
    if (-not (Get-Command "ghq" -ErrorAction SilentlyContinue)) {
      return
    }
    if (-not (Get-Command "fzf" -ErrorAction SilentlyContinue)) {
      return
    }

    $root = (& ghq root).Trim()
    $selected = (& ghq list | & fzf --reverse --height=50%)
    if ($selected) {
      Set-Location (Join-Path $root $selected.Trim())
      [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
      [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }
  }
}

# --- Oh My Posh (prompt theme) ---
if (Get-Command "oh-my-posh" -ErrorAction SilentlyContinue) {
  $ompConfig = Join-Path $HOME ".config\ohmyposh\takuya.omp.json"
  if (Test-Path -LiteralPath $ompConfig) {
    oh-my-posh init pwsh --config $ompConfig | Invoke-Expression
  }
}

function cc {
  & claude --dangerously-skip-permissions @args
}

if (Get-Command "eza" -ErrorAction SilentlyContinue) {
  function ll { & eza -l -g --icons @args }
  function la { & eza -la -g --icons @args }
}

if (Get-Command "nvim" -ErrorAction SilentlyContinue) {
  Set-Alias -Name vim -Value nvim
}

$gitBashCandidates = @()
$programRoots = @($env:ProgramFiles, $env:ProgramW6432, ${env:ProgramFiles(x86)}) | Where-Object { $_ }

foreach ($root in $programRoots) {
  $gitBashCandidates += Join-Path $root "Git\bin\bash.exe"
  $gitBashCandidates += Join-Path $root "Git\usr\bin\bash.exe"
}

$gitBashCandidates = $gitBashCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique

if ($gitBashCandidates.Count -gt 0) {
  $env:CLAUDE_CODE_GIT_BASH_PATH = $gitBashCandidates[0]
}
