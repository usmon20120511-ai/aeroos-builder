param(
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [Parameter(Mandatory = $true)][string]$OutputIso,
    [string]$RecipePath = ''
)

. "$PSScriptRoot\common.ps1"
if (-not $script:AeroLogFile) { Initialize-AeroLog -Path (Join-Path $WorkDir 'logs\04-export.log') }

$state = Get-AeroState -WorkDir $WorkDir
if (-not $RecipePath) { $RecipePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'recipes\aeroos-public.json' }
$recipe = Get-AeroJson -Path $RecipePath
$brand = $recipe.branding
$mount = $state.MountPath
$isoRoot = $state.IsoRoot
$wim = $state.Wim
$name = [string]$brand.imageName
$label = [string]$brand.isoLabel
if ($label.Length -gt 32) { $label = $label.Substring(0, 32) }

Write-AeroLog '=== сохранение и экспорт WIM ==='
Save-AeroWim -Path $mount

# DISM не поддерживает /Set-Image: имя и описание задаются параметрами /Export-Image ниже.
$finalWim = Join-Path $WorkDir 'work\install-final.wim'
if (Test-Path -LiteralPath $finalWim) { Remove-Item -LiteralPath $finalWim -Force }
& dism.exe /Export-Image "/SourceImageFile:$wim" /SourceIndex:1 "/DestinationImageFile:$finalWim" /Compress:max "/DestinationName:$name"
if ($LASTEXITCODE -ne 0) { throw "Экспорт WIM завершился с ошибкой $LASTEXITCODE" }
Write-AeroLog "Итоговый WIM: $((Get-Item -LiteralPath $finalWim).Length) bytes"

Write-AeroLog '=== метка и BCD ==='
$autorun = Join-Path $isoRoot 'autorun.inf'
if (Test-Path -LiteralPath $autorun) {
    # Файлы ISO приходят с атрибутом "только для чтения" — снимаем перед правкой.
    & attrib.exe -r -s -h $autorun 2>&1 | Out-Null
    $text = [IO.File]::ReadAllText($autorun)
    $text = [regex]::Replace($text, '(?m)^label=.*$', ('label=' + $label))
    [IO.File]::WriteAllText($autorun, $text, [Text.Encoding]::ASCII)
    Write-AeroLog "autorun.inf: label=$label"
}

foreach ($rel in @('boot\bcd', 'efi\microsoft\boot\bcd')) {
    $bcd = Join-Path $isoRoot $rel
    if (-not (Test-Path -LiteralPath $bcd)) { Write-AeroLog "Нет $rel, пропуск"; continue }
    # Утилиты пишут диагностику в stderr — гасим её, чтобы не было исключений.
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        & takeown.exe /f $bcd 2>&1 | Out-Null
        & icacls.exe $bcd /grant '*S-1-5-32-544:F' /Q 2>&1 | Out-Null
        & attrib.exe -r -s -h $bcd 2>&1 | Out-Null
    } finally { $ErrorActionPreference = $oldEap }
    foreach ($prop in $brand.bcd.PSObject.Properties) {
        # bcdedit может писать в stderr — не даём PowerShell превратить это в исключение.
        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try {
            $out = & bcdedit.exe /store $bcd /set $prop.Name description $prop.Value 2>&1
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $oldEap }
        if ($code -ne 0) {
            Write-AeroLog "WARN bcd $rel $($prop.Name): $out"
        } else {
            Write-AeroLog "BCD $rel $($prop.Name) = $($prop.Value)"
        }
    }
}

Write-AeroLog '=== замена install.wim ==='
$sources = Join-Path $isoRoot 'sources'
foreach ($old in @((Join-Path $sources 'install.wim'), (Join-Path $sources 'install.esd'))) {
    if (-not (Test-Path -LiteralPath $old)) { continue }
    & attrib.exe -r -s -h $old 2>&1 | Out-Null
    Remove-Item -LiteralPath $old -Force -ErrorAction Stop
}
Copy-Item -LiteralPath $finalWim -Destination (Join-Path $sources 'install.wim') -Force

Write-AeroLog '=== сборка ISO ==='
$oscdimg = Get-AeroOscdimg
$etfsboot = Join-Path $isoRoot 'boot\etfsboot.com'
$efisys = Join-Path $isoRoot 'efi\microsoft\boot\efisys.bin'
foreach ($required in @($etfsboot, $efisys, (Join-Path $isoRoot 'setup.exe'))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Отсутствует загрузочный файл: $required" }
}
$bootData = "2#p0,e,b`"$etfsboot`"#pEF,e,b`"$efisys`""
$outDir = Split-Path -Parent $OutputIso
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
Remove-Item -LiteralPath $OutputIso -Force -ErrorAction SilentlyContinue
& $oscdimg -y -m -o -u2 -udfver102 "-bootdata:$bootData" ("-l" + $label) $isoRoot $OutputIso
if ($LASTEXITCODE -ne 0) { throw "oscdimg завершился с ошибкой $LASTEXITCODE" }
Write-AeroLog "ISO создан: $OutputIso ($((Get-Item -LiteralPath $OutputIso).Length) bytes)"

Write-AeroLog '=== проверка ISO ==='
$mountedImage = Mount-DiskImage -ImagePath $OutputIso -PassThru
try {
    $drive = Get-AeroDriveLetter -MountResult $mountedImage -Label $label
    if (-not $drive) { throw 'Не удалось получить букву итогового ISO' }
    foreach ($rel in @('setup.exe', 'autorun.inf', 'boot\etfsboot.com', 'efi\microsoft\boot\efisys.bin', 'sources\install.wim', 'sources\boot.wim')) {
        $path = Join-Path "${drive}:\" $rel
        if (-not (Test-Path -LiteralPath $path)) { throw "В ISO отсутствует $rel" }
        Write-AeroLog "OK: $rel"
    }
    $imgs = @(Get-WindowsImage -ImagePath "${drive}:\sources\install.wim")
    if ($imgs.Count -ne 1 -or $imgs[0].ImageName -ne $name) { throw "Неожиданное имя образа в ISO: $($imgs[0].ImageName)" }
    Write-AeroLog "Образ в ISO: $($imgs[0].ImageName)"
} finally {
    Dismount-DiskImage -ImagePath $OutputIso | Out-Null
}

$hash = (Get-FileHash -LiteralPath $OutputIso -Algorithm SHA256).Hash
Write-AeroLog "ISO_SHA256=$hash"
Write-AeroLog '4-Export-BuildIso DONE'
