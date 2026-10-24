<#
.SYNOPSIS
    Genera el instalador EXE de Nubix para Windows con Inno Setup (Biglex Modern 2.0).

.DESCRIPTION
    Flujo:
      1. Resuelve la version real del proyecto (src-tauri\tauri.conf.json -> version).
      2. Reescribe packaging\windows\version.iss con esa version.
      3. Compila la app con Tauri sin bundle (--no-bundle: solo afecta a esta
         compilacion de Windows; no se toca la configuracion de macOS/Linux).
      4. Prepara build\inno-staging\app con el ejecutable y sus recursos.
      5. Compila packaging\windows\setup.iss con ISCC.exe y deja el instalador
         en la carpeta de release.

    Antes de invocar ISCC.exe el builder sincroniza la plantilla visual
    compartida y pasa el validador de invariantes de empaquetado
    (Scripts\tools\inno\Check-Packaging.ps1), que aborta la compilacion si el
    arranque post-instalacion vuelve a lanzar la app directamente desde el
    instalador (fallo 0xc00004bc), si el nombre de salida lleva el sufijo
    obsoleto _x64 o si la plantilla visual diverge de la compartida.

    La identidad de actualizacion (AppId en packaging\windows\identity.iss) es
    estable entre versiones: una version nueva actualiza la anterior en el
    mismo directorio en vez de instalar en paralelo.

.PARAMETER Version
    Version concreta a empaquetar. Por defecto, la de tauri.conf.json.

.PARAMETER SkipBuild
    No compila la app: reutiliza el ejecutable ya generado en target\release.

.PARAMETER OutputDirectory
    Carpeta donde se deja el instalador. Por defecto, <proyecto>\release.

.PARAMETER ForceStale
    Empaqueta aunque el ejecutable sea mas viejo que las fuentes. Solo para
    depurar: publicar asi reintroduce el binario obsoleto.

.PARAMETER IsccPath
    Ruta a ISCC.exe. Por defecto se busca en la variable ISCC, en la carpeta
    compartida de herramientas y en las rutas habituales de Inno Setup 6.

.EXAMPLE
    .\scripts\packaging\Build-Installer.ps1
#>
param(
    [string]$Version,
    [switch]$SkipBuild,
    [string]$OutputDirectory,
    # Empaqueta aunque el ejecutable sea mas viejo que las fuentes. Solo para
    # depurar: publicar asi reintroduce el binario obsoleto.
    [switch]$ForceStale,
    [string]$IsccPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$packagingDir = Join-Path $root "packaging\windows"
$setupScript = Join-Path $packagingDir "setup.iss"
$versionScript = Join-Path $packagingDir "version.iss"
$stagingDir = Join-Path $root "build\inno-staging\app"
$tauriConf = Join-Path $root "src-tauri\tauri.conf.json"
$cargoToml = Join-Path $root "src-tauri\Cargo.toml"
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root "release" }

function Resolve-Iscc {
    param([string]$Preferred)

    if ($Preferred -and (Test-Path -LiteralPath $Preferred)) { return $Preferred }

    # Localiza ISCC.exe sin rutas absolutas: primero la copia del workspace,
    # subiendo desde este script; despues el PATH del sistema.
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt 8; $i++) {
        $candidate = Join-Path $dir 'Scripts\tools\InnoSetup\ISCC.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }

    if ($env:ISCC -and (Test-Path -LiteralPath $env:ISCC)) { return $env:ISCC }

    $onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    # Instalacion estandar de Inno Setup 6 (el PATH no siempre lo incluye).
    foreach ($candidate in @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return $null
}

function Write-Step {
    param([string]$Text)
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Fail {
    param([string]$Text)
    Write-Host "ERROR: $Text" -ForegroundColor Red
    throw $Text
}

# --- Puerta de calidad de empaquetado (validador compartido) -----------------
# La plantilla visual y el arranque post-instalacion son fuente unica del
# workspace. Un [Run] editado a mano que lance la app directamente desde el
# instalador hace que el proceso herede su contexto y muera con 0xc00004bc
# (STATUS_REDIRECTION_TRUST_FAILURE), asi que el validador compartido aborta
# la compilacion antes de invocar ISCC.exe.
function Resolve-SharedInno {
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt 8; $i++) {
        $candidate = Join-Path $dir 'Scripts\tools\inno'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Sync-SharedTemplate {
    param([string]$SharedDir, [string]$PackagingDir)
    if (-not $SharedDir) { return }
    $src = Join-Path $SharedDir 'BiglexModernUI.iss'
    $dst = Join-Path $PackagingDir 'BiglexModernUI.iss'
    if ((Test-Path -LiteralPath $src) -and (Test-Path -LiteralPath $PackagingDir)) {
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host "      Plantilla visual sincronizada con la copia compartida del workspace." -ForegroundColor Gray
    }
}

function Assert-PackagingInvariants {
    param([string]$SharedDir, [string[]]$SetupFiles)
    if (-not $SharedDir) {
        Write-Host 'AVISO: no se encontro la carpeta compartida Scripts\tools\inno.' -ForegroundColor Yellow
        Write-Host '       Se omite la validacion de invariantes de empaquetado.' -ForegroundColor Yellow
        return
    }
    $checker = Join-Path $SharedDir 'Check-Packaging.ps1'
    if (-not (Test-Path -LiteralPath $checker)) {
        Write-Host "AVISO: no se encontro $checker. Se omite la validacion." -ForegroundColor Yellow
        return
    }
    # Get-Command puede devolver varias rutas (alias de Store y MSIX): se toma
    # la primera que exista de verdad.
    $shellExe = $null
    foreach ($name in @('pwsh', 'powershell')) {
        foreach ($candidate in @(Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)) {
            if ($candidate.Source -and (Test-Path -LiteralPath $candidate.Source)) {
                $shellExe = $candidate.Source
                break
            }
        }
        if ($shellExe) { break }
    }
    if (-not $shellExe) {
        Write-Host 'AVISO: no se encontro pwsh ni powershell: se omite la validacion.' -ForegroundColor Yellow
        return
    }
    foreach ($setup in $SetupFiles) {
        & $shellExe -NoProfile -ExecutionPolicy Bypass -File $checker -SetupIss $setup
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: las invariantes de empaquetado fallan para $setup." -ForegroundColor Red
            Write-Host '       No se compila el instalador. Corrige lo anterior.' -ForegroundColor Red
            exit 1
        }
    }
}

# --- Candado anti-binario-obsoleto ------------------------------------------
# Tauri incrusta dist/ DENTRO del ejecutable. Si el .exe es mas viejo que el
# codigo fuente o que dist/, el instalador empaqueta un binario obsoleto aunque
# se compile "recien" y aunque dist/ este al dia. Regla de Core:
# Docs/global/architecture/command-scripts-standard.md, principio 2.
function Get-NewestWriteTime {
    param([string[]]$Paths)
    $best = $null
    $bestPath = $null
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $item = if (Test-Path -LiteralPath $path -PathType Container) {
            Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        else {
            Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
        if ($item -and (-not $best -or $item.LastWriteTime -gt $best)) {
            $best = $item.LastWriteTime
            $bestPath = $item.FullName
        }
    }
    return [pscustomobject]@{ Time = $best; Path = $bestPath }
}

function Assert-BinaryFresh {
    param([string]$Exe, [string]$AppRoot, [switch]$Force)
    if (-not (Test-Path -LiteralPath $Exe)) {
        Write-Fail "No se encontro el ejecutable compilado: $Exe`n  Compila la app sin el flag de omision."
    }
    $exeItem = Get-Item -LiteralPath $Exe
    $newest = Get-NewestWriteTime -Paths @(
        (Join-Path $AppRoot 'src'),
        (Join-Path $AppRoot 'src-tauri\src'),
        (Join-Path $AppRoot 'dist'),
        (Join-Path $AppRoot 'src-tauri\Cargo.toml'),
        (Join-Path $AppRoot 'src-tauri\tauri.conf.json'),
        (Join-Path $AppRoot 'src-tauri\build.rs'),
        (Join-Path $AppRoot 'src-tauri\capabilities'),
        (Join-Path $AppRoot 'package.json')
    )
    if (-not $newest.Time) { return }
    if ($exeItem.LastWriteTime -ge $newest.Time) {
        Write-Step "Ejecutable al dia: $($exeItem.LastWriteTime.ToString('dd/MM HH:mm:ss'))"
        return
    }
    $rel = if ($newest.Path) { $newest.Path.Substring($AppRoot.Length).TrimStart('\') } else { '(desconocido)' }
    if ($Force) {
        Write-Host "AVISO: se empaqueta un binario OBSOLETO por -ForceStale." -ForegroundColor Yellow
        Write-Host "       exe $($exeItem.LastWriteTime.ToString('dd/MM HH:mm:ss')) < fuente $($newest.Time.ToString('dd/MM HH:mm:ss')) $rel" -ForegroundColor Yellow
        return
    }
    Write-Fail ("El ejecutable es MAS VIEJO que el codigo fuente:`n" +
                "  ejecutable : $($exeItem.LastWriteTime.ToString('dd/MM HH:mm:ss'))  $Exe`n" +
                "  fuente     : $($newest.Time.ToString('dd/MM HH:mm:ss'))  $rel`n`n" +
                "Tauri incrusta dist/ dentro del ejecutable, asi que un .exe viejo publica`n" +
                "tambien un frontend viejo aunque dist/ este al dia. Vuelve a compilar la app" +
                ", o usa -ForceStale solo para depurar.")
}

function Assert-SemanticVersion {
    param([string]$Value)
    if ($Value -notmatch '^\d+\.\d+\.\d+$') {
        throw "Version no valida (se espera x.y.z): '$Value'."
    }
}

function Invoke-Checked {
    param(
        [string]$Executable,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $cwd = $root
    if ($WorkingDirectory) { $cwd = $WorkingDirectory }
    Push-Location $cwd
    try {
        & $Executable @ArgumentList
        $code = $LASTEXITCODE
    }
    finally {
        Pop-Location
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) {
        throw "Fallo ($code): $Executable $($ArgumentList -join ' ')"
    }
    return $code
}

# --- 1. Version -------------------------------------------------------------
$conf = Get-Content -LiteralPath $tauriConf -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $Version) { $Version = $conf.version }
Assert-SemanticVersion $Version
Write-Host "[1/5] Version del instalador: $Version (tauri.conf.json: $($conf.version))" -ForegroundColor Yellow

# --- 2. version.iss ---------------------------------------------------------
$versionContent = @(
    "; ---------------------------------------------------------------------------",
    "; version.iss - generada por scripts\packaging\Build-Installer.ps1 con la",
    "; version real del proyecto (src-tauri\tauri.conf.json -> version).",
    "; No editar a mano: se reescribe en cada build.",
    "; ---------------------------------------------------------------------------",
    "#define MyAppVersion `"$Version`""
) -join "`r`n"
Set-Content -LiteralPath $versionScript -Value $versionContent -Encoding UTF8
Write-Host "      $versionScript actualizado" -ForegroundColor Gray

# --- 3. Build de la app -----------------------------------------------------
# El nombre del binario lo fija Cargo con el nombre del paquete (src-tauri\Cargo.toml).
$cargoText = Get-Content -LiteralPath $cargoToml -Raw -Encoding UTF8
$pkgMatch = [regex]::Match($cargoText, '(?m)^name\s*=\s*"([^"]+)"')
if (-not $pkgMatch.Success) { throw "No se pudo leer el nombre del paquete en $cargoToml." }
$binName = $pkgMatch.Groups[1].Value
$releaseExe = Join-Path $root "src-tauri\target\release\$binName.exe"

if (-not $SkipBuild) {
    Write-Host "[2/5] Compilando Nubix con Tauri (sin bundle de Tauri en Windows)..." -ForegroundColor Yellow
    # --no-bundle solo afecta a esta invocacion en Windows: no se modifica
    # tauri.conf.json, de modo que macOS y Linux conservan su empaquetado.
    Invoke-Checked -Executable "npm.cmd" -ArgumentList @("run", "tauri", "build", "--", "--no-bundle") | Out-Null
}
else {
    Write-Host "[2/5] Build omitido: se reutiliza el ejecutable existente." -ForegroundColor DarkYellow
}

if (-not (Test-Path -LiteralPath $releaseExe)) {
    throw "No se encontro el ejecutable $releaseExe. Ejecuta el build sin -SkipBuild."
}
Assert-BinaryFresh -Exe $releaseExe -AppRoot $root -Force:$ForceStale

# --- 4. Staging -------------------------------------------------------------
Write-Host "[3/5] Preparando el contenido del instalador..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $stagingDir) {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

$releaseDir = Split-Path -Parent $releaseExe
$staged = 0
Get-ChildItem -LiteralPath $releaseDir -File | Where-Object {
    # Solo el ejecutable de la app y los recursos que Tauri deja a su lado
    # (WebView2Loader.dll, etc.). Se excluyen artefactos intermedios de Cargo.
    $_.Name -eq "$binName.exe" -or
    $_.Extension -eq ".dll" -or
    $_.Name -eq "$binName.msi"
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stagingDir $_.Name) -Force
    $staged++
}
if (-not (Test-Path -LiteralPath (Join-Path $stagingDir "$binName.exe"))) {
    throw "El staging no contiene $binName.exe."
}
Write-Host "      $staged fichero(s) preparado(s) en $stagingDir" -ForegroundColor Gray

# --- 5. Compilacion del instalador -----------------------------------------
if (-not $IsccPath) { $IsccPath = Resolve-Iscc }
if (-not $IsccPath) { Write-Fail 'No se localizo ISCC.exe en Scripts\tools\InnoSetup ni en el PATH.' }
$iscc = $IsccPath
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Write-Host "[4/5] Compilando el instalador con Inno Setup ($iscc)..." -ForegroundColor Yellow
$sharedInno = Resolve-SharedInno
Sync-SharedTemplate -SharedDir $sharedInno -PackagingDir $packagingDir
Assert-PackagingInvariants -SharedDir $sharedInno -SetupFiles @($setupScript)
Invoke-Checked -Executable $iscc -ArgumentList @($setupScript, "/O$OutputDirectory") | Out-Null

$installerName = "Nubix-Setup-$Version.exe"
$installer = Join-Path $OutputDirectory $installerName
if (-not (Test-Path -LiteralPath $installer)) {
    $produced = Get-ChildItem -LiteralPath $OutputDirectory -Filter "*.exe" -File | Select-Object -ExpandProperty Name
    throw "ISCC termino sin error pero no se encontro '$installerName'. Produjo: $($produced -join ', ')"
}

Write-Host "[5/5] Instalador generado: $installer ($([math]::Round((Get-Item -LiteralPath $installer).Length / 1MB, 2)) MB)" -ForegroundColor Green
Write-Output $installer
