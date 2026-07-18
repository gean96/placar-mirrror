<#
.SYNOPSIS
    Hot-swap do codigo Python no APK ja compilado, sem rebuild Flutter/Gradle/NDK.

.DESCRIPTION
    Flet 0.86 / serious_python 4.x embute o app em assets/app.zip (nao mais em
    flutter_assets/app/). Na primeira execucao apos install/update ele unpack
    version-keyed para files/flet/app (chave = versionName+versionCode).

    Este script:
      1. Gera um novo app.zip a partir de src/ (.pyc com Python do bundle Android).
      2. Substitui assets/app.zip no APK (auto-detecta layout 0.85 legado se existir).
      3. Incrementa versionCode no AndroidManifest.binario para forcar re-extract
         (release nao e debuggable: run-as nao limpa files/flet/.key).
      4. zipalign + apksigner + adb install -r.
      5. Opcionalmente inicia o app e confirma DEV_STAMP no logcat.

    Use so para mudancas Python. Kotlin/manifest/nativo => build_apk_v2.ps1.

    Cada fast_push incrementa versionCode acima do device/APK base (nao so +1
    sobre o build original), senao o Flet 0.86 nao re-extrai o app.zip.

.PARAMETER Launch
    Inicia o app apos instalar.

.PARAMETER Log
    Segue o logcat apos instalar/iniciar.

.PARAMETER SourcePy
    Envia .py fonte em vez de .pyc. Por padrao empacota .pyc (Python 3.14).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fast_push.ps1 -Launch -Log
#>
[CmdletBinding()]
param(
    [string]$Apk = "",
    [switch]$Launch,
    [switch]$Log,
    [switch]$SourcePy
)

# Por padrao empacota .pyc (Python 3.14 = bundle Android do Flet 0.86).
$Compile = -not $SourcePy
$AndroidPythonVersion = "3.14"

$ErrorActionPreference = "Stop"
$sw = [System.Diagnostics.Stopwatch]::StartNew()

function Write-Step($msg) { Write-Host "[fast_push] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[fast_push] $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "[fast_push] $msg" -ForegroundColor Yellow }

$Root = Split-Path -Parent $PSScriptRoot
$SrcDir = Join-Path $Root "src"
$PackageId = "com.yourdomain.yourapp" # <--- SUBSTITUA PELO ID DO SEU APLICATIVO

if (-not (Test-Path -LiteralPath $SrcDir)) { throw "src/ nao encontrado em $Root" }

# --- 1. Localizar o APK release ja compilado ---------------------------------
if (-not $Apk) {
    $candidates = @(
        (Join-Path $Root "dist\flet-apk-arm64-v8a\YourAppName.apk"),
        (Join-Path $Root "dist\YourAppName.apk"),
        (Join-Path $Root "build\flutter\build\app\outputs\flutter-apk\app-release.apk")
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { $Apk = $c; break }
    }
}
if (-not $Apk -or -not (Test-Path -LiteralPath $Apk)) {
    throw "APK nao encontrado.`nRode o build completo ao menos uma vez."
}
Write-Step "APK base: $Apk"

# --- 2. Localizar build-tools (apksigner + zipalign + aapt) ------------------
$sdk = $env:ANDROID_SDK_ROOT
if (-not $sdk) { $sdk = $env:ANDROID_HOME }
if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$buildToolsRoot = Join-Path $sdk "build-tools"
if (-not (Test-Path -LiteralPath $buildToolsRoot)) { throw "build-tools nao encontrado em $buildToolsRoot" }

$apksigner = $null; $zipalign = $null; $aapt = $null
foreach ($d in (Get-ChildItem $buildToolsRoot -Directory | Sort-Object Name -Descending)) {
    $a = Join-Path $d.FullName "apksigner.bat"
    $z = Join-Path $d.FullName "zipalign.exe"
    $p = Join-Path $d.FullName "aapt.exe"
    if ((Test-Path $a) -and (Test-Path $z)) {
        $apksigner = $a
        $zipalign = $z
        if (Test-Path $p) { $aapt = $p }
        break
    }
}
if (-not $apksigner) { throw "apksigner/zipalign nao encontrados em $buildToolsRoot" }
Write-Step "build-tools: $(Split-Path -Parent $apksigner | Split-Path -Leaf)"

# --- 3. Assinatura (keystore + senhas) ---------------------------------------
$localSigning = Join-Path $PSScriptRoot "android-signing.local.ps1"
if (Test-Path -LiteralPath $localSigning) { . $localSigning }

$storePass = $env:FLET_ANDROID_SIGNING_KEY_STORE_PASSWORD
if (-not $storePass) { $storePass = $env:ANDROID_KEYSTORE_PASSWORD }
$keyPass = $env:FLET_ANDROID_SIGNING_KEY_PASSWORD
if (-not $keyPass) { $keyPass = $env:ANDROID_KEY_PASSWORD }
if (-not $keyPass) { $keyPass = $storePass }

# Padrão para debug keystore se nenhuma variável de ambiente for configurada
$keyStore = Join-Path $env:USERPROFILE ".android\debug.keystore"
$keyAlias = "androiddebugkey"
if ($storePass -eq $null -or $storePass -eq "") {
    $storePass = "android"
    $keyPass = "android"
}

# Se existir keystore customizada definida nas variáveis de ambiente, ajuste:
if ($env:FLET_ANDROID_SIGNING_KEY_STORE) {
    $keyStore = $env:FLET_ANDROID_SIGNING_KEY_STORE
}

if (-not (Test-Path -LiteralPath $keyStore)) { throw "Keystore nao encontrado: $keyStore" }
Write-Step "Keystore: $keyStore (alias=$keyAlias)"

# Detecta Python do bundle (libpython3.XX.so) se existir no APK
if ($aapt) {
    $pyLib = (& $aapt list $Apk 2>$null | Select-String -Pattern 'libpython(\d+\.\d+)\.so' | Select-Object -First 1)
    if ($pyLib -and $pyLib.Matches.Count -gt 0) {
        $AndroidPythonVersion = $pyLib.Matches[0].Groups[1].Value
        Write-Step "Python do APK: $AndroidPythonVersion"
    }
}

# --- 4. Montar novo app.zip a partir de src/ ---------------------------------
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$tmp = Join-Path $env:TEMP ("fastpush_" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$appZip = Join-Path $tmp "app.zip"

Write-Step "Gerando app.zip a partir de src/ ..."

# Carimbo unico: main.py loga DEV_STAMP=<isto> no boot (procure no logcat).
$devStamp = "fastpush-" + (Get-Date -Format "yyyyMMdd-HHmmss")
$stampFile = Join-Path $tmp "__dev_stamp__.txt"
[System.IO.File]::WriteAllText($stampFile, $devStamp)
Write-Ok "DEV_STAMP=$devStamp (procure este texto no logcat apos abrir o app)"

$excludeDirs = @("__pycache__", ".dart_tool", "build")

function Add-FileToZip {
    param($Archive, [string]$FullPath, [string]$EntryPath)
    $entry = $Archive.CreateEntry($EntryPath, [System.IO.Compression.CompressionLevel]::Optimal)
    $es = $entry.Open()
    $fs = [System.IO.File]::OpenRead($FullPath)
    try { $fs.CopyTo($es) } finally { $fs.Dispose(); $es.Dispose() }
}

$pycTmp = $null
if ($Compile) {
    $pycTmp = Join-Path $tmp "pysrc"
    Copy-Item -Recurse -Force $SrcDir $pycTmp
    Get-ChildItem $pycTmp -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "Compilando .pyc (Python $AndroidPythonVersion via uv)..."
    $pyAndroid = (& uv python find $AndroidPythonVersion).Trim()
    if (-not $pyAndroid) {
        Write-Step "Instalando Python $AndroidPythonVersion via uv..."
        & uv python install $AndroidPythonVersion | Out-Null
        $pyAndroid = (& uv python find $AndroidPythonVersion).Trim()
    }
    if (-not $pyAndroid) { throw "Python $AndroidPythonVersion nao encontrado via uv (necessario para .pyc)." }
    & $pyAndroid -m compileall -b -q $pycTmp | Out-Null
    Get-ChildItem $pycTmp -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $sourceRoot = $pycTmp
} else {
    $sourceRoot = $SrcDir
}

$fileCount = 0
$fsOut = [System.IO.File]::Open($appZip, [System.IO.FileMode]::Create)
$zip = New-Object System.IO.Compression.ZipArchive($fsOut, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Add-FileToZip -Archive $zip -FullPath $stampFile -EntryPath "__dev_stamp__.txt"
    $script:fileCount++
    $rootLen = (Resolve-Path $sourceRoot).Path.TrimEnd('\').Length + 1
    Get-ChildItem $sourceRoot -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($rootLen)
        $parts = $rel -split '[\\/]'
        if ($parts | Where-Object { $excludeDirs -contains $_ }) { return }
        $ext = $_.Extension.ToLower()
        if ($Compile) {
            if ($ext -eq ".py") { return }
        } else {
            if ($ext -eq ".pyc") { return }
        }
        $entryPath = ($rel -replace '\\', '/')
        Add-FileToZip -Archive $zip -FullPath $_.FullName -EntryPath $entryPath
        $script:fileCount++
    }
} finally {
    $zip.Dispose(); $fsOut.Dispose()
}
Write-Ok "app.zip gerado ($fileCount arquivos, $([math]::Round((Get-Item $appZip).Length/1MB,2)) MB)"

$hash = (Get-FileHash $appZip -Algorithm SHA256).Hash.ToLower()
Write-Step "app.zip sha256: $hash"

# --- 5. Copiar APK, detectar layout, substituir app.zip ----------------------
$workApk = Join-Path $tmp "app-fastpush.apk"
Copy-Item -LiteralPath $Apk -Destination $workApk -Force

# Flet 0.86+: assets/app.zip | legado 0.85: assets/flutter_assets/app/app.zip
$entryZipModern = "assets/app.zip"
$entryZipLegacy = "assets/flutter_assets/app/app.zip"
$entryHashLegacy = "assets/flutter_assets/app/app.zip.hash"

Write-Step "Substituindo entradas no APK..."
$fs = [System.IO.File]::Open($workApk, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
$arc = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Update)
$entryZip = $null
$layout = $null
try {
    if ($arc.GetEntry($entryZipModern)) {
        $entryZip = $entryZipModern
        $layout = "0.86"
    } elseif ($arc.GetEntry($entryZipLegacy)) {
        $entryZip = $entryZipLegacy
        $layout = "0.85-legacy"
    } else {
        throw "Nem '$entryZipModern' nem '$entryZipLegacy' encontrados no APK. Rebuild completo necessario."
    }
    Write-Step "Layout APK: $layout ($entryZip)"

    $old = $arc.GetEntry($entryZip)
    if ($old) { $old.Delete() }
    Add-FileToZip -Archive $arc -FullPath $appZip -EntryPath $entryZip

    # Legado 0.85: manter hash se a entrada existir
    if ($layout -eq "0.85-legacy") {
        $hashFile = Join-Path $tmp "app.zip.hash"
        [System.IO.File]::WriteAllText($hashFile, $hash)
        $he = $arc.GetEntry($entryHashLegacy)
        if ($he) { $he.Delete() }
        Add-FileToZip -Archive $arc -FullPath $hashFile -EntryPath $entryHashLegacy
    }
} finally {
    $arc.Dispose(); $fs.Dispose()
}

# --- 6. Bump versionCode (forca re-extract version-keyed no 0.86) ------------
$bumpScript = Join-Path $PSScriptRoot "apk_bump_version_code.py"
$versionStateFile = Join-Path $Root "dist\.fast_push_version_code"
$newVersionCode = $null
if (Test-Path -LiteralPath $bumpScript) {
    $baseCode = $null
    if ($aapt) {
        $badging = & $aapt dump badging $workApk 2>$null
        $bm = [regex]::Match(($badging | Out-String), "versionCode='(\d+)'")
        if ($bm.Success) { $baseCode = [int]$bm.Groups[1].Value }
    }

    $deviceCode = $null
    try {
        $pkgDump = cmd /c "adb shell dumpsys package $PackageId 2>nul"
        $dm = [regex]::Match(($pkgDump | Out-String), "versionCode=(\d+)")
        if ($dm.Success) { $deviceCode = [int]$dm.Groups[1].Value }
    } catch { }

    $savedCode = $null
    if (Test-Path -LiteralPath $versionStateFile) {
        $raw = (Get-Content -LiteralPath $versionStateFile -Raw).Trim()
        if ($raw -match '^\d+$') { $savedCode = [int]$raw }
    }

    $floor = @($baseCode, $deviceCode, $savedCode) | Where-Object { $_ -ne $null } | Measure-Object -Maximum
    $targetCode = 1
    if ($null -ne $floor.Maximum) { $targetCode = [int]$floor.Maximum + 1 }

    Write-Step "Incrementando versionCode no AndroidManifest (forcar unpack)..."
    Write-Step ("Refs: base={0} device={1} saved={2} -> alvo={3}" -f $baseCode, $deviceCode, $savedCode, $targetCode)
    $bumpOut = & uv run python $bumpScript $workApk $targetCode 2>&1
    $bumpOut | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "Falha ao bump versionCode. O Python novo pode nao ser extraido ate limpar dados do app."
    } else {
        $m = [regex]::Match(($bumpOut | Out-String), 'versionCode\s+(\d+)\s*->\s*(\d+)')
        if ($m.Success) {
            $newVersionCode = $m.Groups[2].Value
            New-Item -ItemType Directory -Force -Path (Split-Path $versionStateFile) | Out-Null
            [System.IO.File]::WriteAllText($versionStateFile, "$newVersionCode`n")
        }
    }
} else {
    Write-Warn2 "Script apk_bump_version_code.py ausente; pulando bump de versionCode."
}

# --- 7. zipalign + apksigner -------------------------------------------------
$alignedApk = Join-Path $tmp "app-fastpush-aligned.apk"
Write-Step "zipalign..."
& $zipalign -f 4 $workApk $alignedApk
if ($LASTEXITCODE -ne 0) { throw "zipalign falhou (exit $LASTEXITCODE)" }

Write-Step "apksigner..."
& $apksigner sign `
    --ks $keyStore `
    --ks-key-alias $keyAlias `
    --ks-pass "pass:$storePass" `
    --key-pass "pass:$keyPass" `
    $alignedApk
if ($LASTEXITCODE -ne 0) { throw "apksigner falhou (exit $LASTEXITCODE)" }

# --- 8. Instalar -------------------------------------------------------------
Write-Step "adb install -r --no-incremental ..."
& adb install -r --no-incremental $alignedApk
if ($LASTEXITCODE -ne 0) {
    Write-Warn2 "install --no-incremental falhou; tentando adb install -r padrao..."
    & adb install -r $alignedApk
}
if ($LASTEXITCODE -ne 0) { throw "adb install falhou (exit $LASTEXITCODE)" }

# Best-effort: se o APK for debuggable, limpa o marker tambem
$clearOut = cmd /c "adb shell run-as $PackageId sh -c `"rm -f files/flet/.key && rm -rf files/flet/app`" 2>&1"
if ($LASTEXITCODE -eq 0) {
    Write-Ok "Marker files/flet/.key limpo via run-as."
} else {
    Write-Step "run-as indisponivel (release) - confia no bump de versionCode."
}

$sw.Stop()
Write-Ok ("Concluido em {0:N1}s" -f $sw.Elapsed.TotalSeconds)
if ($newVersionCode) { Write-Ok "versionCode instalado: $newVersionCode" }
Write-Warn2 "ATENCAO: fast_push so troca Python. Mudancas Kotlin/Nativas exigem build completo."

# --- 9. Launch + confirmar DEV_STAMP no logcat --------------------------------
if ($Launch -or $Log) {
    Write-Step "Reiniciando app para extrair o Python novo..."
    Start-Sleep -Seconds 1
    cmd /c "adb shell am force-stop $PackageId >nul 2>nul"
    Start-Sleep -Seconds 1
    cmd /c "adb shell am start -n $PackageId/.MainActivity >nul 2>nul"

    Write-Step "Aguardando DEV_STAMP=$devStamp no logcat..."
    $confirmed = $false
    $needle = "DEV_STAMP=$devStamp"
    $appPid = ""
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 800
        if (-not $appPid) {
            $appPid = (cmd /c "adb shell pidof $PackageId 2>nul").Trim()
            if (-not $appPid) { continue }
            Write-Step "App PID=$appPid - lendo logcat desse processo..."
        }
        $dump = cmd /c "adb logcat -d --pid $appPid 2>nul"
        if (("$dump") -like "*$needle*") {
            $confirmed = $true
            break
        }
    }
    if ($confirmed) {
        Write-Ok "CONFIRMADO no device: $needle"
    } else {
        Write-Warn2 "Nao vi $needle no logcat em 45s."
    }
}
if ($Log) {
    Write-Step "Seguindo logs (Ctrl+C para sair)..."
    & adb logcat SimpleMonday:V serious_python:V MainActivity:V flutter:V "*:E"
}

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
