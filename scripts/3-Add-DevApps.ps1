param(
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [string]$AppsConfig = '',
    [string]$AppsCache = '',
    [bool]$IncludeExplorerPatcher = $true,
    [switch]$SkipApps
)

. "$PSScriptRoot\common.ps1"
if (-not $script:AeroLogFile) { Initialize-AeroLog -Path (Join-Path $WorkDir 'logs\03-apps.log') }

$state = Get-AeroState -WorkDir $WorkDir
if (-not $AppsConfig) { $AppsConfig = Join-Path (Split-Path $PSScriptRoot -Parent) 'config\apps.json' }
$config = Get-AeroJson -Path $AppsConfig
$mount = $state.MountPath
if (-not (Test-Path -LiteralPath (Join-Path $mount 'Windows\System32\config\SYSTEM'))) { throw "Образ не смонтирован: $mount" }

$appsDir = Join-Path $mount 'Windows\Setup\Scripts\Apps'
$scriptDir = Join-Path $mount 'Windows\Setup\Scripts'
$downloads = Join-Path $WorkDir 'downloads'
New-Item -ItemType Directory -Force -Path $appsDir, $downloads | Out-Null

$installLines = @()

if ($SkipApps) {
    Write-AeroLog 'Приложения пропущены по флагу -SkipApps'
} else {
    foreach ($item in @($config.items)) {
        if (-not $item.enabled) { continue }
        if ($item.id -eq 'explorerpatcher' -and -not $IncludeExplorerPatcher) {
            Write-AeroLog 'ExplorerPatcher отключён флагом -NoExplorerPatcher'
            continue
        }

        $file = [string]$item.file
        $dest = Join-Path $downloads $file

        if ($AppsCache -and (Test-Path -LiteralPath (Join-Path $AppsCache $file))) {
            Write-AeroLog "Из кэша: $file"
            Copy-Item -LiteralPath (Join-Path $AppsCache $file) -Destination $dest -Force
        }

        if (-not (Test-Path -LiteralPath $dest)) {
            Write-AeroLog "Скачивание: $($item.url)"
            & curl.exe -fL --retry 3 --retry-delay 5 --max-time 1800 -o $dest $item.url
            if ($LASTEXITCODE -ne 0 -and $item.fallbackUrl) {
                Write-AeroLog "Основная ссылка не сработала, пробуем запасную"
                Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
                & curl.exe -fL --retry 3 --retry-delay 5 --max-time 1800 -o $dest $item.fallbackUrl
            }
            if ($LASTEXITCODE -ne 0) { throw "Не удалось скачать $file" }
        }

        $actualHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
        if ($item.sha256) {
            if ($actualHash -ne [string]$item.sha256) {
                throw "Хэш не совпал у $file`nожидался: $($item.sha256)`nполучен:  $actualHash"
            }
            Write-AeroLog "SHA256 OK: $file"
        } else {
            Write-AeroLog "SHA256 (эталон не задан): $file = $actualHash"
        }

        try {
            $sig = Get-AuthenticodeSignature -LiteralPath $dest
            if ($sig.Status -ne 'Valid') {
                if ($item.allowUnsigned) {
                    Write-AeroLog "INFO $file подписан? status=$($sig.Status) (разрешено для этого компонента)"
                } else {
                    Write-AeroLog "WARN $file подпись status=$($sig.Status) signer=$($sig.SignerCertificate.Subject)"
                }
            } else {
                Write-AeroLog "Подпись OK: $file"
            }
        } catch { Write-AeroLog "WARN проверка подписи $file : $($_.Exception.Message)" }

        Copy-Item -LiteralPath $dest -Destination (Join-Path $appsDir $file) -Force
        Write-AeroLog "В образе: $file ($((Get-Item -LiteralPath (Join-Path $appsDir $file)).Length) bytes)"

        $installLines += 'echo Installing {0}... >> "%LOG%"' -f $item.label
        if ($item.installer -eq 'msi') {
            $installLines += 'msiexec /i "%APPS%\{0}" {1}' -f $file, $item.args
        } else {
            $installLines += '"%APPS%\{0}" {1}' -f $file, $item.args
        }
        $installLines += 'echo {0} exit=%errorlevel% >> "%LOG%"' -f $item.id
    }
}

$templatePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config\SetupComplete.cmd.template'
$template = [IO.File]::ReadAllText($templatePath)
$content = $template.Replace('{{LOGNAME}}', [string]$config.logName)
$content = $content.Replace('{{INSTALL_LINES}}', ($installLines -join "`r`n"))
$setupComplete = Join-Path $scriptDir 'SetupComplete.cmd'
[IO.File]::WriteAllText($setupComplete, $content, [Text.Encoding]::ASCII)
Write-AeroLog "SetupComplete.cmd записан: $setupComplete"
Get-Content -LiteralPath $setupComplete | ForEach-Object { Write-AeroLog "  $_" }

Write-AeroLog '3-Add-DevApps DONE'
