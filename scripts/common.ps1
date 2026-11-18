# Общие функции для aeroOS Builder. Только текст, без бинарников.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:AeroLogFile = $null
$script:AeroUtf8 = New-Object System.Text.UTF8Encoding($false)
Import-Module Dism -Force -ErrorAction SilentlyContinue

function Initialize-AeroLog {
    param([Parameter(Mandatory = $true)][string]$Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $script:AeroLogFile = $Path
    Write-AeroLog "Log: $Path"
}

function Write-AeroLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
    if ($script:AeroLogFile) {
        try { [IO.File]::AppendAllText($script:AeroLogFile, $line + "`r`n", $script:AeroUtf8) } catch { }
    }
}

function Assert-AeroAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Нужны права администратора. Открой PowerShell от имени администратора.'
    }
}

function Get-AeroJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Нет файла: $Path" }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Save-AeroState {
    param([Parameter(Mandatory = $true)][string]$WorkDir, [Parameter(Mandatory = $true)][hashtable]$State)
    $path = Join-Path $WorkDir 'build-state.json'
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-AeroState {
    param([Parameter(Mandatory = $true)][string]$WorkDir)
    $path = Join-Path $WorkDir 'build-state.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "Нет файла состояния $path. Сначала запусти 0-Prepare-Image.ps1." }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Invoke-RegQuiet {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { & reg.exe @Arguments 2>&1 | Out-Null; return $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
}

function Invoke-RegCapture {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { return (& reg.exe @Arguments 2>&1 | Out-String) }
    finally { $ErrorActionPreference = $old }
}

function Set-AeroRegValue {
    param(
        [Parameter(Mandatory = $true)][string]$Hive,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Type = 'DWord',
        [object]$Value = 0
    )
    $key = 'HKLM\' + $Hive + '\' + $Path
    $regType = if ($Type -eq 'String') { 'REG_SZ' } else { 'REG_DWORD' }
    $code = Invoke-RegQuiet @('add', $key, '/v', $Name, '/t', $regType, '/d', ([string]$Value), '/f')
    if ($code -ne 0) { Write-AeroLog "WARN registry $key\$Name exit=$code" }
}

function Remove-AeroRegValue {
    param([Parameter(Mandatory = $true)][string]$Hive, [Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Name)
    $key = 'HKLM\' + $Hive + '\' + $Path
    $null = Invoke-RegQuiet @('delete', $key, '/v', $Name, '/f')
}

function Get-AeroControlSets {
    param([Parameter(Mandatory = $true)][string]$Hive)
    $out = Invoke-RegCapture @('query', ('HKLM\' + $Hive))
    $matches = [regex]::Matches($out, ('HKEY_LOCAL_MACHINE\\' + $Hive + '\\(ControlSet\d+)'))
    $result = @($matches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($result.Count -eq 0) { $result = @('ControlSet001') }
    return $result
}

function Unload-AeroHive {
    param([Parameter(Mandatory = $true)][string]$Hive)
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    for ($i = 0; $i -lt 6; $i++) {
        $code = Invoke-RegQuiet @('unload', ('HKLM\' + $Hive))
        if ($code -eq 0) { return $true }
        Start-Sleep -Milliseconds 750
    }
    Write-AeroLog "WARN не удалось выгрузить HKLM\$Hive"
    return $false
}

function Remove-AeroTree {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    & takeown.exe /F $Path /R /D Y 2>&1 | Out-Null
    & icacls.exe $Path /grant '*S-1-5-32-544:F' /T 2>&1 | Out-Null
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    return $true
}

function Rename-AeroDisabled {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $name = (Split-Path $Path -Leaf) + '.disabled-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Rename-Item -LiteralPath $Path -NewName $name -ErrorAction Stop
    return $true
}

function Mount-AeroWim {
    param([Parameter(Mandatory = $true)][string]$Wim, [Parameter(Mandatory = $true)][string]$Path)
    Import-Module Dism -Force
    $existing = @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | Where-Object { $_.MountPath -eq $Path })
    if ($existing.Count -gt 0) { Write-AeroLog "WIM уже смонтирован: $Path"; return }
    if (-not (Test-Path -LiteralPath $Wim)) { throw "Нет WIM: $Wim" }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Mount-WindowsImage -ImagePath $Wim -Index 1 -Path $Path -ErrorAction Stop | Out-Null
    Write-AeroLog "WIM смонтирован: $Path"
}

function Save-AeroWim {
    param([Parameter(Mandatory = $true)][string]$Path)
    $existing = @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | Where-Object { $_.MountPath -eq $Path })
    if ($existing.Count -eq 0) {
        Write-AeroLog "WIM уже сохранён и отмонтирован, пропуск: $Path"
        return
    }
    Dismount-WindowsImage -Path $Path -Save -ErrorAction Stop | Out-Null
    Write-AeroLog "WIM сохранён: $Path"
}

function Discard-AeroWim {
    param([string]$Path)
    if (-not $Path) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $existing = @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | Where-Object { $_.MountPath -eq $Path })
    if ($existing.Count -gt 0) {
        Dismount-WindowsImage -Path $Path -Discard -ErrorAction SilentlyContinue | Out-Null
        Write-AeroLog "Отмонтировано без сохранения: $Path"
    }
}

function Get-AeroOscdimg {
    $candidates = @(
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files (x86)\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    )
    $found = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $found) { throw 'oscdimg.exe не найден. Установи Windows ADK → Deployment Tools.' }
    return $found
}

function Get-AeroDriveLetter {
    param($MountResult, [string]$Label)
    $drive = ($MountResult | Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -First 1).DriveLetter
    if (-not $drive) {
        Start-Sleep -Seconds 3
        $vol = Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.FileSystemLabel -eq $Label } | Select-Object -First 1
        $drive = $vol.DriveLetter
    }
    return $drive
}
