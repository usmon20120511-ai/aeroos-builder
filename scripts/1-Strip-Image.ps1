param(
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [string]$RecipePath = '',
    [string]$DriverFolder = ''
)

. "$PSScriptRoot\common.ps1"
if (-not $script:AeroLogFile) { Initialize-AeroLog -Path (Join-Path $WorkDir 'logs\01-strip.log') }

$state = Get-AeroState -WorkDir $WorkDir
if (-not $RecipePath) { $RecipePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'recipes\aeroos-public.json' }
$recipe = Get-AeroJson -Path $RecipePath
$mount = $state.MountPath
if (-not (Test-Path -LiteralPath (Join-Path $mount 'Windows\System32\config\SYSTEM'))) { throw "Образ не смонтирован: $mount" }

Write-AeroLog "Профиль: $($recipe.name)"

$removedApps = 0
$removedCaps = 0
$removedFeats = 0
$removedPkgs = 0
$removedTasks = 0

Write-AeroLog '=== provisioned apps ==='
$prefixes = @($recipe.remove.appPrefixes)
foreach ($app in @(Get-AppxProvisionedPackage -Path $mount)) {
    $hit = $false
    foreach ($prefix in $prefixes) {
        if ($app.PackageName -eq $prefix -or $app.PackageName -like "$prefix*") { $hit = $true; break }
    }
    if (-not $hit) { continue }
    try {
        Remove-AppxProvisionedPackage -Path $mount -PackageName $app.PackageName -ErrorAction Stop | Out-Null
        $removedApps++
        Write-AeroLog "REMOVED app: $($app.PackageName)"
    } catch { Write-AeroLog "WARN app $($app.PackageName): $($_.Exception.Message)" }
}

Write-AeroLog '=== capabilities ==='
foreach ($cap in @(Get-WindowsCapability -Path $mount)) {
    if (@($recipe.remove.capabilities) -contains $cap.Name) {
        try {
            Remove-WindowsCapability -Path $mount -Name $cap.Name -ErrorAction Stop | Out-Null
            $removedCaps++
            Write-AeroLog "REMOVED capability: $($cap.Name)"
        } catch { Write-AeroLog "WARN capability $($cap.Name): $($_.Exception.Message)" }
    }
}

Write-AeroLog '=== optional features ==='
foreach ($f in @(Get-WindowsOptionalFeature -Path $mount)) {
    if (@($recipe.remove.features) -contains $f.FeatureName -and $f.State -eq 'Enabled') {
        try {
            Disable-WindowsOptionalFeature -Path $mount -FeatureName $f.FeatureName -Remove -NoRestart -ErrorAction Stop | Out-Null
            $removedFeats++
            Write-AeroLog "REMOVED feature: $($f.FeatureName)"
        } catch { Write-AeroLog "WARN feature $($f.FeatureName): $($_.Exception.Message)" }
    }
}

Write-AeroLog '=== component packages ==='
$allowedLangs = @($recipe.language)
foreach ($p in @(Get-WindowsPackage -Path $mount)) {
    if ($p.PackageState -ne 'Installed') { continue }
    $hit = $false
    foreach ($pattern in @($recipe.remove.packagePatterns)) {
        if ($p.PackageName -match $pattern) { $hit = $true; break }
    }
    if ($p.PackageName -match 'Client-LanguagePack-Package') {
        $keep = $false
        foreach ($lang in $allowedLangs) {
            if ($p.PackageName -match ('~' + [regex]::Escape($lang) + '~')) { $keep = $true; break }
        }
        if (-not $keep) { $hit = $true }
    }
    if (-not $hit) { continue }
    try {
        Remove-WindowsPackage -Path $mount -PackageName $p.PackageName -NoRestart -ErrorAction Stop | Out-Null
        $removedPkgs++
        Write-AeroLog "REMOVED package: $($p.PackageName)"
    } catch { Write-AeroLog "WARN package $($p.PackageName): $($_.Exception.Message)" }
}

Write-AeroLog '=== scheduled tasks ==='
foreach ($rel in @($recipe.remove.taskPaths)) {
    if (Remove-AeroTree -Path (Join-Path $mount $rel)) {
        $removedTasks++
        Write-AeroLog "REMOVED task path: $rel"
    }
}

if ($recipe.defenderEdge.enabled) {
    Write-AeroLog '=== Defender / Edge payloads ==='
    foreach ($rel in @($recipe.defenderEdge.disablePaths)) {
        try {
            if (Rename-AeroDisabled -Path (Join-Path $mount $rel)) { Write-AeroLog "DISABLED path: $rel" }
        } catch { Write-AeroLog "WARN path $rel : $($_.Exception.Message)" }
    }
    foreach ($file in @($recipe.defenderEdge.disableFiles)) {
        try {
            if (Rename-AeroDisabled -Path (Join-Path $mount ('Windows\System32\' + $file))) { Write-AeroLog "DISABLED file: $file" }
        } catch { Write-AeroLog "WARN file $file : $($_.Exception.Message)" }
    }
    $pattern = [string]$recipe.defenderEdge.disableShortcutPatterns
    if ($pattern) {
        $startRoots = @(
            (Join-Path $mount 'ProgramData\Microsoft\Windows\Start Menu\Programs'),
            (Join-Path $mount 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs')
        )
        foreach ($root in $startRoots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pattern })) {
                try {
                    if (Rename-AeroDisabled -Path $item.FullName) { Write-AeroLog "DISABLED shortcut: $($item.FullName)" }
                } catch { }
            }
        }
    }
}

Write-AeroLog '=== offline registry ==='
$config = Join-Path $mount 'Windows\System32\config'
foreach ($h in 'AERO_SYSTEM', 'AERO_SOFTWARE', 'AERO_DEFAULT') { $null = Invoke-RegQuiet @('unload', ('HKLM\' + $h)) }
if ((Invoke-RegQuiet @('load', 'HKLM\AERO_SYSTEM', (Join-Path $config 'SYSTEM'))) -ne 0) { throw 'Не удалось загрузить SYSTEM' }
if ((Invoke-RegQuiet @('load', 'HKLM\AERO_SOFTWARE', (Join-Path $config 'SOFTWARE'))) -ne 0) { throw 'Не удалось загрузить SOFTWARE' }
if ((Invoke-RegQuiet @('load', 'HKLM\AERO_DEFAULT', (Join-Path $mount 'Users\Default\NTUSER.DAT'))) -ne 0) { throw 'Не удалось загрузить NTUSER.DAT' }

try {
    $controlSets = Get-AeroControlSets -Hive 'AERO_SYSTEM'

    Write-AeroLog '=== services ==='
    foreach ($service in @($recipe.disableServices)) {
        foreach ($cs in $controlSets) {
            $key = "$cs\Services\$service"
            if ((Invoke-RegQuiet @('query', ('HKLM\AERO_SYSTEM\' + $key))) -eq 0) {
                Set-AeroRegValue -Hive 'AERO_SYSTEM' -Path $key -Name 'Start' -Type 'DWord' -Value 4
                Set-AeroRegValue -Hive 'AERO_SYSTEM' -Path $key -Name 'DelayedAutoStart' -Type 'DWord' -Value 0
                Write-AeroLog "DISABLED service: $cs\$service"
            }
        }
    }

    foreach ($hive in @('SYSTEM', 'SOFTWARE', 'DEFAULT')) {
        $entries = @($recipe.registry.$hive)
        if ($entries.Count -eq 0) { continue }
        Write-AeroLog "=== registry: $hive ($($entries.Count) values) ==="
        foreach ($entry in $entries) {
            $paths = @()
            if ($hive -eq 'SYSTEM' -and $entry.path -like '*{ControlSet}*') {
                foreach ($cs in $controlSets) { $paths += ($entry.path -replace '\{ControlSet\}', $cs) }
            } else {
                $paths += [string]$entry.path
            }
            foreach ($path in $paths) {
                Set-AeroRegValue -Hive ('AERO_' + $hive) -Path $path -Name $entry.name -Type $entry.type -Value $entry.value
            }
        }
    }
} finally {
    foreach ($h in 'AERO_DEFAULT', 'AERO_SOFTWARE', 'AERO_SYSTEM') { Unload-AeroHive -Hive $h | Out-Null }
}

Write-AeroLog '=== component store cleanup ==='
& dism.exe /Image:"$mount" /Cleanup-Image /StartComponentCleanup /ResetBase /LogPath:"$(Join-Path $WorkDir 'logs\dism-cleanup.log')"
if ($LASTEXITCODE -ne 0) { Write-AeroLog "WARN StartComponentCleanup exit=$LASTEXITCODE" } else { Write-AeroLog 'Component store cleaned' }

if ($DriverFolder) {
    if (-not (Test-Path -LiteralPath $DriverFolder)) { throw "Нет папки с драйверами: $DriverFolder" }
    Write-AeroLog '=== injecting YOUR drivers ==='
    foreach ($d in @(Get-ChildItem -LiteralPath $DriverFolder -Directory)) {
        try {
            Add-WindowsDriver -Path $mount -Driver $d.FullName -Recurse -ErrorAction Stop | Out-Null
            Write-AeroLog "INJECTED driver: $($d.Name)"
        } catch { Write-AeroLog "WARN driver $($d.Name): $($_.Exception.Message)" }
    }
} else {
    Write-AeroLog 'Драйверы не внедрялись (по умолчанию).'
}

Write-AeroLog "ИТОГО: apps=$removedApps caps=$removedCaps features=$removedFeats packages=$removedPkgs tasks=$removedTasks"
Write-AeroLog '1-Strip-Image DONE'
