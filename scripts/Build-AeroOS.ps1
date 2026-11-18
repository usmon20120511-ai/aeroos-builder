param(
    [Parameter(Mandatory = $true)][string]$SourceIso,
    [string]$OutputIso = '',
    [string]$WorkDir = '',
    [int]$EditionIndex = 0,
    [string]$Recipe = '',
    [string]$AppsConfig = '',
    [string]$AppsCache = '',
    [string]$DriverFolder = '',
    [string]$Wallpaper = '',
    [string]$IntroVideo = '',
    [string]$IntroPhoto = '',
    [switch]$NoExplorerPatcher,
    [switch]$SkipApps
)

. "$PSScriptRoot\common.ps1"

Assert-AeroAdmin

if (-not $Recipe) { $Recipe = Join-Path (Split-Path $PSScriptRoot -Parent) 'recipes\aeroos-public.json' }
if (-not $AppsConfig) { $AppsConfig = Join-Path (Split-Path $PSScriptRoot -Parent) 'config\apps.json' }
if (-not $WorkDir) { $WorkDir = Join-Path $env:TEMP ('aeroos-build-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
if (-not $OutputIso) {
    $OutputIso = Join-Path ([Environment]::GetFolderPath('Desktop')) ('aeroOS-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.iso')
}

New-Item -ItemType Directory -Force -Path $WorkDir, (Join-Path $WorkDir 'logs') | Out-Null
Initialize-AeroLog -Path (Join-Path $WorkDir 'logs\build.log')

Write-AeroLog '====================================================='
Write-AeroLog ' aeroOS Builder'
Write-AeroLog ' В пакете нет бинарников Windows. ISO подаёшь сам.'
Write-AeroLog '====================================================='
Write-AeroLog "SourceIso  = $SourceIso"
Write-AeroLog "OutputIso  = $OutputIso"
Write-AeroLog "WorkDir    = $WorkDir"
Write-AeroLog "Recipe     = $Recipe"
Write-AeroLog "AppsConfig = $AppsConfig"
if ($DriverFolder) { Write-AeroLog "DriverFolder = $DriverFolder (драйверы будут внедрены!)" }
if ($IntroVideo) { Write-AeroLog "IntroVideo = $IntroVideo (личный контент!)" }
if ($IntroPhoto) { Write-AeroLog "IntroPhoto = $IntroPhoto (личный контент!)" }

try {
    Write-AeroLog '--- STEP 0: подготовка образа ---'
    & (Join-Path $PSScriptRoot '0-Prepare-Image.ps1') -SourceIso $SourceIso -WorkDir $WorkDir -EditionIndex $EditionIndex

    Write-AeroLog '--- STEP 1: удаление лишнего ---'
    & (Join-Path $PSScriptRoot '1-Strip-Image.ps1') -WorkDir $WorkDir -RecipePath $Recipe -DriverFolder $DriverFolder

    Write-AeroLog '--- STEP 2: брендинг ---'
    & (Join-Path $PSScriptRoot '2-Set-AeroOSBrand.ps1') -WorkDir $WorkDir -RecipePath $Recipe -Wallpaper $Wallpaper -IntroVideo $IntroVideo -IntroPhoto $IntroPhoto

    Write-AeroLog '--- STEP 3: приложения ---'
    & (Join-Path $PSScriptRoot '3-Add-DevApps.ps1') -WorkDir $WorkDir -AppsConfig $AppsConfig -AppsCache $AppsCache -IncludeExplorerPatcher:$(-not $NoExplorerPatcher) -SkipApps:$SkipApps

    Write-AeroLog '--- STEP 4: экспорт и сборка ISO ---'
    & (Join-Path $PSScriptRoot '4-Export-BuildIso.ps1') -WorkDir $WorkDir -OutputIso $OutputIso -RecipePath $Recipe

    Write-AeroLog '====================================================='
    Write-AeroLog "ГОТОВО: $OutputIso"
    Write-AeroLog "SHA256: $((Get-FileHash -LiteralPath $OutputIso -Algorithm SHA256).Hash)"
    Write-AeroLog "Лог: $(Join-Path $WorkDir 'logs\build.log')"
    Write-AeroLog 'Не забудь проверить ISO в виртуальной машине.'
    Write-AeroLog '====================================================='
} catch {
    Write-AeroLog "ОШИБКА: $($_.Exception.Message)"
    $statePath = Join-Path $WorkDir 'build-state.json'
    if (Test-Path -LiteralPath $statePath) {
        try {
            $s = Get-AeroState -WorkDir $WorkDir
            Discard-AeroWim -Path $s.MountPath
        } catch { }
    }
    foreach ($h in 'AERO_SYSTEM', 'AERO_SOFTWARE', 'AERO_DEFAULT') { Unload-AeroHive -Hive $h | Out-Null }
    throw
}
