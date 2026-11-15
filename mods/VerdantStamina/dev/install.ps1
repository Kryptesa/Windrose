param(
    [string]$GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Windrose',
    [switch]$IncludeLoader
)
$ErrorActionPreference = 'Stop'
$projectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$binaryDir = [IO.Path]::GetFullPath((Join-Path $GameDir 'R5\Binaries\Win64'))
$expectedExe = Join-Path $binaryDir 'Windrose-Win64-Shipping.exe'
if (-not (Test-Path -LiteralPath $expectedExe -PathType Leaf)) { throw 'Windrose client executable not found' }
$gameRunning = [bool](Get-Process -Name 'Windrose-Win64-Shipping','Windrose' -ErrorAction SilentlyContinue)
if ($gameRunning -and $IncludeLoader) { throw 'Close Windrose before installing the loader' }
$manifestPath = Join-Path $binaryDir 'VerdantStamina-install.json'
$previous = @{}
if (Test-Path -LiteralPath $manifestPath) {
    foreach ($entry in (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).files) {
        $previous[$entry.path] = $entry.sha256
    }
}
$files = @{}
$sourceMod = Join-Path $projectDir 'mods\VerdantStamina'
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $sourceMod 'Scripts'),(Join-Path $sourceMod 'Assets') -Recurse -File) {
    $relative = [IO.Path]::GetRelativePath($sourceMod,$file.FullName)
    $files[(Join-Path 'ue4ss\Mods\VerdantStamina' $relative)] = $file.FullName
}
$stageDir = Join-Path $projectDir 'build\install'
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
$enabledPath = Join-Path $stageDir 'enabled.txt'
[IO.File]::WriteAllText($enabledPath,'')
$files['ue4ss\Mods\VerdantStamina\enabled.txt'] = $enabledPath
if ($IncludeLoader) {
    $loaderDir = Join-Path $projectDir 'tools\ue4ss'
    foreach ($relative in @('dwmapi.dll','ue4ss\UE4SS.dll')) {
        $target = Join-Path $binaryDir $relative
        if ((Test-Path -LiteralPath $target) -and -not $previous.ContainsKey($relative)) {
            throw "Existing loader file is not owned by this installer: $target"
        }
        $files[$relative] = Join-Path $loaderDir $relative
    }
    $ini = Get-Content -LiteralPath (Join-Path $loaderDir 'ue4ss\UE4SS-settings.ini') -Raw
    $ini = $ini -replace '(?m)^MajorVersion =\s*$', 'MajorVersion = 5'
    $ini = $ini -replace '(?m)^MinorVersion =\s*$', 'MinorVersion = 6'
    $iniPath = Join-Path $stageDir 'UE4SS-settings.ini'
    [IO.File]::WriteAllText($iniPath,$ini)
    $files['ue4ss\UE4SS-settings.ini'] = $iniPath
    $modsPath = Join-Path $stageDir 'mods.txt'
    [IO.File]::WriteAllText($modsPath,"VerdantStamina : 1`r`n")
    $files['ue4ss\Mods\mods.txt'] = $modsPath
}
$resolvedFiles = @()
foreach ($relative in $files.Keys) {
    $target = [IO.Path]::GetFullPath((Join-Path $binaryDir $relative))
    if (-not $target.StartsWith($binaryDir + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Target escapes the game directory: $target"
    }
    $source = $files[$relative]
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing staged source: $source" }
    if (Test-Path -LiteralPath $target) {
        if ($gameRunning -and $relative -eq 'ue4ss\Mods\VerdantStamina\Scripts\main.lua' -and
            (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
            throw 'Scheduler changed; close Windrose once before this update'
        }
        if (-not $previous.ContainsKey($relative)) { throw "Refusing to overwrite an unowned file: $target" }
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $previous[$relative]) {
            throw "Installed file has local changes; preserve it before updating: $target"
        }
    }
    $resolvedFiles += [pscustomobject]@{path=$relative;source=$source;target=$target;sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash}
}
# All paths/collisions are verified before the first game-directory write.
$backupDir = Join-Path $projectDir ('build\install-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
foreach ($file in $resolvedFiles) {
    if (Test-Path -LiteralPath $file.target) {
        $backup = Join-Path $backupDir $file.path
        New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
        Copy-Item -LiteralPath $file.target -Destination $backup
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $file.target) -Force | Out-Null
    Copy-Item -LiteralPath $file.source -Destination $file.target -Force
    if ((Get-FileHash -LiteralPath $file.target -Algorithm SHA256).Hash -ne $file.sha256) { throw "Installed hash mismatch: $($file.target)" }
}
$owned = @{}
foreach ($relative in $previous.Keys) { $owned[$relative] = $previous[$relative] }
foreach ($file in $resolvedFiles) { $owned[$file.path] = $file.sha256 }
$manifest = [ordered]@{version=(Get-Content -LiteralPath (Join-Path $projectDir 'mods\VerdantStamina\VERSION') -Raw).Trim();files=@($owned.Keys | Sort-Object | ForEach-Object { [ordered]@{path=$_;sha256=$owned[$_]} })}
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 6))
# Written last: a running stable scheduler now reloads the completed source set.
[IO.File]::WriteAllText((Join-Path $binaryDir 'ue4ss\Mods\VerdantStamina\Scripts\reload.txt'),[guid]::NewGuid().ToString())
Write-Output "Installed $($resolvedFiles.Count) files; manifest: $manifestPath"
