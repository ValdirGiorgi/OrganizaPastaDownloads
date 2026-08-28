[CmdletBinding()]
param(
    [switch]$Pause,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = "Stop"

$appDir = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $appDir "build\organiza_downloads.exe"
$dataDir = Join-Path $env:LOCALAPPDATA "organiza_downloads"
$logDir = Join-Path $dataDir "logs"
$csvDir = Join-Path $dataDir "relatorios"
New-Item -ItemType Directory -Force -Path $logDir, $csvDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir "$stamp.log"

function Write-Log {
    param([string]$Message)
    $Message | Tee-Object -FilePath $logFile -Append
}

if (-not (Test-Path -LiteralPath $bin)) {
    Write-Log "Binario nao encontrado em $bin"
    Write-Log "Rode scripts\build_windows.ps1 para gerar o binario."
    exit 1
}

# Equivalente ao xdg-user-dir do Linux: respeita pastas redirecionadas
# (OneDrive, particao separada) em vez de assumir %USERPROFILE%.
function Resolve-UserFolder {
    param([string]$ValueName, [string]$Fallback)
    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    try {
        $raw = (Get-ItemProperty -Path $key -Name $ValueName -ErrorAction Stop).$ValueName
        $resolved = [Environment]::ExpandEnvironmentVariables($raw)
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            return $resolved
        }
    } catch {
    }
    return $Fallback
}

function Invoke-Scan {
    param([string]$Target)
    if (Test-Path -LiteralPath $Target) {
        Write-Log "=== Organizando: $Target ==="
        & $bin scan $Target --mode real --hash-duplicates --csv $csvDir @ExtraArgs *>&1 |
            Tee-Object -FilePath $logFile -Append
        Write-Log ""
    } else {
        Write-Log "Pasta nao encontrada, pulando: $Target"
    }
}

$downloadsDir = Resolve-UserFolder "{374DE290-123F-4565-9164-39C4925E467B}" (Join-Path $env:USERPROFILE "Downloads")
$desktopDir = Resolve-UserFolder "Desktop" (Join-Path $env:USERPROFILE "Desktop")

Invoke-Scan $downloadsDir
Invoke-Scan $desktopDir

Write-Log "Log completo em: $logFile"

if ($Pause) {
    Read-Host "Pressione Enter para fechar..." | Out-Null
}
