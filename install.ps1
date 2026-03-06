$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$DotfilesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$NvimSrc = Join-Path $DotfilesDir "nvim"
$NvimDst = Join-Path $env:LOCALAPPDATA "nvim"
$ProfileSrc = Join-Path $DotfilesDir ".ps_profile.ps1"
$ProfileDst = $PROFILE.CurrentUserCurrentHost
$BinDir = Join-Path $HOME ".local\bin"
$ImSelectDst = Join-Path $BinDir "im-select.exe"

function New-BackupName {
  param([Parameter(Mandatory = $true)][string]$Path)
  return "$Path.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
}

function Resolve-AbsolutePath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Get-LinkTargetAbsolute {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $item = Get-Item -LiteralPath $Path -Force
  $isReparsePoint = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
  if (-not $isReparsePoint) {
    return $null
  }

  $target = $item.Target
  if (-not $target) {
    return $null
  }

  if ($target -is [System.Array]) {
    $target = $target[0]
  }

  if (-not [IO.Path]::IsPathRooted($target)) {
    $target = Join-Path (Split-Path -Parent $Path) $target
  }

  try {
    return (Resolve-Path -LiteralPath $target -ErrorAction Stop).Path
  } catch {
    return $null
  }
}

function New-ManagedLink {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][ValidateSet("File", "Directory")][string]$ItemType,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $sourceResolved = Resolve-AbsolutePath -Path $Source
  if (-not $sourceResolved) {
    throw "Missing source for $Name: $Source"
  }

  $dstDir = Split-Path -Parent $Destination
  if (-not (Test-Path -LiteralPath $dstDir)) {
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
  }

  if (Test-Path -LiteralPath $Destination) {
    $targetResolved = Get-LinkTargetAbsolute -Path $Destination
    if ($targetResolved -and ($targetResolved -eq $sourceResolved)) {
      Write-Host "$Name link already exists: $Destination -> $Source"
      return
    }

    $item = Get-Item -LiteralPath $Destination -Force
    $isReparsePoint = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isReparsePoint) {
      Remove-Item -LiteralPath $Destination -Recurse -Force
    } else {
      $backup = New-BackupName -Path $Destination
      Move-Item -LiteralPath $Destination -Destination $backup
      Write-Host "Backed up existing $Name to: $backup"
    }
  }

  try {
    New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -Force | Out-Null
    Write-Host "Linked $Name: $Destination -> $Source"
  } catch {
    Write-Warning "Failed to create symlink for $Name. Falling back to copy."
    Write-Warning "Enable Developer Mode or run PowerShell as Administrator to allow symlink creation."

    if ($ItemType -eq "Directory") {
      Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    } else {
      Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
    Write-Host "Copied $Name to: $Destination"
  }
}

function Test-ImSelectExists {
  if (Get-Command "im-select.exe" -ErrorAction SilentlyContinue) {
    return $true
  }
  return (Test-Path -LiteralPath $ImSelectDst)
}

function Install-ImSelect {
  if (Test-ImSelectExists) {
    Write-Host "im-select.exe is already installed."
    return
  }

  if (-not (Test-Path -LiteralPath $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
  }

  $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
  if ($winget) {
    try {
      $packageId = "daipeihust.im-select"
      Write-Host "Installing im-select via winget..."
      & $winget.Source install --id $packageId -e --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity --silent
      if (Test-ImSelectExists) {
        Write-Host "im-select installation completed."
        return
      }
    } catch {
      Write-Warning "winget install failed; trying GitHub release fallback."
    }
  }

  Write-Host "Installing im-select from GitHub release..."
  $tmpDir = Join-Path ([IO.Path]::GetTempPath()) "dotfiles-im-select"
  if (Test-Path -LiteralPath $tmpDir) {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/daipeihust/im-select/releases/latest" -Headers @{ "User-Agent" = "dotfiles-installer" }
  $asset = $release.assets |
    Where-Object { $_.name -match "(windows|win|im-select\.exe)" -and $_.name -match "(\.zip|\.exe)$" } |
    Select-Object -First 1

  if (-not $asset) {
    $asset = $release.assets | Where-Object { $_.name -match "(\.zip|\.exe)$" } | Select-Object -First 1
  }
  if (-not $asset) {
    throw "Could not find a downloadable im-select asset in latest release."
  }

  $downloadPath = Join-Path $tmpDir $asset.name
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath

  if ($downloadPath -like "*.zip") {
    Expand-Archive -LiteralPath $downloadPath -DestinationPath $tmpDir -Force
    $exe = Get-ChildItem -LiteralPath $tmpDir -Recurse -Filter "im-select.exe" | Select-Object -First 1
    if (-not $exe) {
      throw "im-select.exe not found in downloaded zip."
    }
    Copy-Item -LiteralPath $exe.FullName -Destination $ImSelectDst -Force
  } else {
    Copy-Item -LiteralPath $downloadPath -Destination $ImSelectDst -Force
  }

  Remove-Item -LiteralPath $tmpDir -Recurse -Force
  Write-Host "Installed im-select.exe to: $ImSelectDst"
}

Write-Host "=== dotfiles installer (PowerShell) ==="

$runningOnWindows = $false
if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
  $runningOnWindows = [bool]$IsWindows
} else {
  $runningOnWindows = ($env:OS -eq "Windows_NT")
}

if (-not $runningOnWindows) {
  throw "This script is for Windows only."
}

New-ManagedLink -Source $NvimSrc -Destination $NvimDst -ItemType Directory -Name "nvim"
New-ManagedLink -Source $ProfileSrc -Destination $ProfileDst -ItemType File -Name "PowerShell profile"
Install-ImSelect

Write-Host "Done."
