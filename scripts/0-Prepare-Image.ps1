param(
    [Parameter(Mandatory = $true)][string]$SourceIso,
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [int]$EditionIndex = 0
)

. "$PSScriptRoot\common.ps1"
if (-not $script:AeroLogFile) { Initialize-AeroLog -Path (Join-Path $WorkDir 'logs\00-prepare.log') }

Assert-AeroAdmin

$dirs = @(
    $WorkDir,
    (Join-Path $WorkDir 'work'),
    (Join-Path $WorkDir 'logs'),
    (Join-Path $WorkDir 'downloads'),
    (Join-Path $WorkDir 'iso-root')
)
foreach ($d in $dirs) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

if (-not (Test-Path -LiteralPath $SourceIso)) { throw "Нет исходного ISO: $SourceIso" }
$sourceHash = (Get-FileHash -LiteralPath $SourceIso -Algorithm SHA256).Hash
Write-AeroLog "Исходный ISO: $SourceIso"
Write-AeroLog "SHA256: $sourceHash"

$isoRoot = Join-Path $WorkDir 'iso-root'
$mount   = Join-Path $WorkDir 'work\mount'
$wim     = Join-Path $WorkDir 'work\install-source.wim'

Write-AeroLog 'Копирование содержимого ISO (загрузчики и setup.exe остаются родными)...'
Get-ChildItem -LiteralPath $isoRoot -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$image = Mount-DiskImage -ImagePath $SourceIso -PassThru
try {
    $drive = ($image | Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -First 1).DriveLetter
    if (-not $drive) {
        Start-Sleep -Seconds 3
        $drive = (Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.DriveLetter } | Select-Object -First 1).DriveLetter
    }
    if (-not $drive) { throw 'Не удалось получить букву смонтированного ISO' }
    Write-AeroLog "ISO смонтирован: ${drive}:"
    & robocopy.exe "${drive}:\" $isoRoot /E /R:1 /W:1 /NFL /NDL /NP /NJH /NJS /COPY:DAT /DCOPY:DAT | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy завершился с кодом $LASTEXITCODE" }
} finally {
    Dismount-DiskImage -ImagePath $SourceIso | Out-Null
    Write-AeroLog 'ISO отмонтирован'
}

$srcInstall = @(
    (Join-Path $isoRoot 'sources\install.wim'),
    (Join-Path $isoRoot 'sources\install.esd')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $srcInstall) { throw 'В ISO нет sources\install.wim или install.esd' }
Write-AeroLog "Файл образов: $srcInstall"

Import-Module Dism -Force
$images = @(Get-WindowsImage -ImagePath $srcInstall)
$images | Select-Object ImageIndex, ImageName, ImageDescription | Format-Table -AutoSize | Out-String | Write-Host

if ($EditionIndex -gt 0) {
    $target = $images | Where-Object { $_.ImageIndex -eq $EditionIndex } | Select-Object -First 1
    if (-not $target) { throw "В ISO нет издания с индексом $EditionIndex" }
} else {
    # Исключаем не те издания: в русской локали "Workstation" и "Education" пишутся по-русски.
    $exclude = '\bN\b|Workstation|for Workstations|рабочих станций|Education|образовательных|Enterprise|Корпоративный|Server'
    $pro = @($images | Where-Object { $_.ImageName -match 'Pro' -and $_.ImageName -notmatch $exclude })
    $exact = @($pro | Where-Object { $_.ImageName -match '^Windows 11 Pro\s*$' })
    if ($exact.Count -gt 0) { $pro = $exact }
    if ($pro.Count -eq 0) { $pro = @($images | Where-Object { $_.ImageName -match 'Pro' }) }
    if ($pro.Count -eq 0) { $pro = $images }
    $target = $pro | Sort-Object { if ($_.ImageDescription -match 'ru-RU') { 0 } else { 1 } } | Select-Object -First 1
}
Write-AeroLog "Выбрано издание: index=$($target.ImageIndex) name=$($target.ImageName)"

if (Test-Path -LiteralPath $wim) { Remove-Item -LiteralPath $wim -Force }
Export-WindowsImage -SourceImagePath $srcInstall -SourceIndex $target.ImageIndex -DestinationImagePath $wim -CompressionType Max -CheckIntegrity | Out-Null
Write-AeroLog "Образ экспортирован: $wim"

Discard-AeroWim -Path $mount
Mount-AeroWim -Wim $wim -Path $mount

$state = @{
    SourceIso     = $SourceIso
    SourceSha256  = $sourceHash
    WorkDir       = $WorkDir
    IsoRoot       = $isoRoot
    Wim           = $wim
    MountPath     = $mount
    ImageIndex    = $target.ImageIndex
    ImageName     = $target.ImageName
    Created       = (Get-Date).ToString('o')
}
Save-AeroState -WorkDir $WorkDir -State $state
Write-AeroLog '0-Prepare-Image DONE'
