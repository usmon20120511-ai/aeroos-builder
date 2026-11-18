param(
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [string]$RecipePath = '',
    [string]$Wallpaper = '',
    [string]$IntroVideo = '',
    [string]$IntroPhoto = ''
)

. "$PSScriptRoot\common.ps1"
if (-not $script:AeroLogFile) { Initialize-AeroLog -Path (Join-Path $WorkDir 'logs\02-brand.log') }

$state = Get-AeroState -WorkDir $WorkDir
if (-not $RecipePath) { $RecipePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'recipes\aeroos-public.json' }
$recipe = Get-AeroJson -Path $RecipePath
$brand = $recipe.branding
$mount = $state.MountPath
if (-not (Test-Path -LiteralPath (Join-Path $mount 'Windows\System32\config\SYSTEM'))) { throw "Образ не смонтирован: $mount" }

$introDir = Join-Path $mount 'Windows\Setup\Scripts\aeroOS'
if ($IntroVideo -or $IntroPhoto) { New-Item -ItemType Directory -Force -Path $introDir | Out-Null }

if ($IntroVideo) {
    if (-not (Test-Path -LiteralPath $IntroVideo)) { throw "Нет видео: $IntroVideo" }
    Copy-Item -LiteralPath $IntroVideo -Destination (Join-Path $introDir 'intro.mp4') -Force
    Write-AeroLog "Добавлено видео: $IntroVideo"

    $html = @'
<!doctype html>
<html><head><meta charset="utf-8"><title>aeroOS</title>
<style>html,body{margin:0;background:#000;overflow:hidden;width:100%;height:100%}video{width:100vw;height:100vh;object-fit:contain;background:#000}</style>
</head><body><video id="v" autoplay muted playsinline><source src="intro.mp4" type="video/mp4"></video>
<script>var v=document.getElementById('v');v.play().catch(function(){});</script></body></html>
'@
    [IO.File]::WriteAllText((Join-Path $introDir 'intro.html'), $html, [Text.Encoding]::ASCII)

    $player = @'
$ErrorActionPreference = "SilentlyContinue"
$log = "C:\ProgramData\aeroOS\intro.log"
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
$base = "C:\Windows\Setup\Scripts\aeroOS"
$html = Join-Path $base "intro.html"
"aeroOS intro start $(Get-Date)" | Out-File -Append -Encoding utf8 $log
$chromeCandidates = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$chrome = $chromeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $chrome) { "Chrome not found" | Out-File -Append -Encoding utf8 $log; exit 0 }
$profile = Join-Path $env:LOCALAPPDATA "aeroOS\ChromeIntro"
New-Item -ItemType Directory -Force -Path $profile | Out-Null
$argLine = '--kiosk --autoplay-policy=no-user-gesture-required --no-first-run --no-default-browser-check --disable-session-crashed-bubble --user-data-dir="' + $profile + '" "' + $html + '"'
$p = Start-Process -FilePath $chrome -ArgumentList $argLine -PassThru
Start-Sleep -Seconds 12
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$profile*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
"aeroOS intro finish $(Get-Date)" | Out-File -Append -Encoding utf8 $log
'@
    [IO.File]::WriteAllText((Join-Path $introDir 'play-intro.ps1'), $player, (New-Object System.Text.UTF8Encoding($false)))
    Write-AeroLog 'Плеер вступления создан'
}

if ($IntroPhoto) {
    if (-not (Test-Path -LiteralPath $IntroPhoto)) { throw "Нет фото: $IntroPhoto" }
    Copy-Item -LiteralPath $IntroPhoto -Destination (Join-Path $introDir 'intro-photo.jpg') -Force
    Copy-Item -LiteralPath $IntroPhoto -Destination (Join-Path $mount 'Windows\Web\Wallpaper\aeroOS-intro.jpg') -Force
    Write-AeroLog "Добавлено фото: $IntroPhoto"
}

Write-AeroLog '=== загрузка офлайн-кустов ==='
$config = Join-Path $mount 'Windows\System32\config'
foreach ($h in 'AERO_SYSTEM', 'AERO_SOFTWARE', 'AERO_DEFAULT') { $null = Invoke-RegQuiet @('unload', ('HKLM\' + $h)) }
if ((Invoke-RegQuiet @('load', 'HKLM\AERO_SYSTEM', (Join-Path $config 'SYSTEM'))) -ne 0) { throw 'SYSTEM load failed' }
if ((Invoke-RegQuiet @('load', 'HKLM\AERO_SOFTWARE', (Join-Path $config 'SOFTWARE'))) -ne 0) { throw 'SOFTWARE load failed' }
if ((Invoke-RegQuiet @('load', 'HKLM\AERO_DEFAULT', (Join-Path $mount 'Users\Default\NTUSER.DAT'))) -ne 0) { throw 'DEFAULT load failed' }

try {
    Write-AeroLog '=== брендинг ==='
    Set-AeroRegValue -Hive 'AERO_SOFTWARE' -Path 'Microsoft\Windows NT\CurrentVersion' -Name 'ProductName' -Type 'String' -Value $brand.productName
    Set-AeroRegValue -Hive 'AERO_SOFTWARE' -Path 'Microsoft\Windows\CurrentVersion\OEMInformation' -Name 'Manufacturer' -Type 'String' -Value $brand.manufacturer
    Set-AeroRegValue -Hive 'AERO_SOFTWARE' -Path 'Microsoft\Windows\CurrentVersion\OEMInformation' -Name 'Model' -Type 'String' -Value $brand.model
    Set-AeroRegValue -Hive 'AERO_SOFTWARE' -Path 'Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'LegalNoticeCaption' -Type 'String' -Value $brand.legalNoticeCaption
    Set-AeroRegValue -Hive 'AERO_SOFTWARE' -Path 'Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'LegalNoticeText' -Type 'String' -Value $brand.legalNoticeText

    foreach ($cs in @(Get-AeroControlSets -Hive 'AERO_SYSTEM')) {
        Set-AeroRegValue -Hive 'AERO_SYSTEM' -Path "$cs\Control\ComputerName\ComputerName" -Name 'ComputerName' -Type 'String' -Value $brand.computerName
        Set-AeroRegValue -Hive 'AERO_SYSTEM' -Path "$cs\Control\ComputerName\ActiveComputerName" -Name 'ComputerName' -Type 'String' -Value $brand.computerName
        Set-AeroRegValue -Hive 'AERO_SYSTEM' -Path "$cs\Services\Tcpip\Parameters" -Name 'Hostname' -Type 'String' -Value $brand.computerName
    }

    Write-AeroLog '=== обои / блокировочный экран ==='
    $wallpaperPath = [string]$brand.wallpaper
    if ($Wallpaper) {
        if (-not (Test-Path -LiteralPath $Wallpaper)) { throw "Нет файла обоев: $Wallpaper" }
        Copy-Item -LiteralPath $Wallpaper -Destination (Join-Path $mount 'Windows\Web\Wallpaper\aeroOS-custom.jpg') -Force
        $wallpaperPath = 'C:\Windows\Web\Wallpaper\aeroOS-custom.jpg'
        Write-AeroLog 'Добавлены свои обои'
    } elseif ($IntroPhoto) {
        $wallpaperPath = 'C:\Windows\Web\Wallpaper\aeroOS-intro.jpg'
    }
    Set-AeroRegValue -Hive 'AERO_DEFAULT' -Path 'Control Panel\Desktop' -Name 'WallPaper' -Type 'String' -Value $wallpaperPath
    Set-AeroRegValue -Hive 'AERO_DEFAULT' -Path 'Control Panel\Desktop' -Name 'WallpaperStyle' -Type 'String' -Value '10'
    Set-AeroRegValue -Hive 'AERO_DEFAULT' -Path 'Control Panel\Desktop' -Name 'TileWallpaper' -Type 'String' -Value '0'

    if ($IntroPhoto) {
        Set-AeroRegValue -Hive 'AERO_SOFTWARE' -Path 'Policies\Microsoft\Windows\System' -Name 'LockScreenImage' -Type 'String' -Value 'C:\Windows\Web\Wallpaper\aeroOS-intro.jpg'
    } else {
        Remove-AeroRegValue -Hive 'AERO_SOFTWARE' -Path 'Policies\Microsoft\Windows\System' -Name 'LockScreenImage'
        Write-AeroLog 'Политика LockScreenImage не задана (публичный профиль)'
    }

    if ($IntroVideo) {
        $run = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\aeroOS\play-intro.ps1"'
        Set-AeroRegValue -Hive 'AERO_SOFTWARE' -Path 'Microsoft\Windows\CurrentVersion\Run' -Name 'aeroOSIntro' -Type 'String' -Value $run
    } else {
        Remove-AeroRegValue -Hive 'AERO_SOFTWARE' -Path 'Microsoft\Windows\CurrentVersion\Run' -Name 'aeroOSIntro'
        Write-AeroLog 'Автозапуск видео не задан (публичный профиль)'
    }
} finally {
    foreach ($h in 'AERO_DEFAULT', 'AERO_SOFTWARE', 'AERO_SYSTEM') { Unload-AeroHive -Hive $h | Out-Null }
}

Write-AeroLog '2-Set-AeroOSBrand DONE'
