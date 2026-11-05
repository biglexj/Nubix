$ErrorActionPreference = 'Stop'

# Refresca los iconos de Nubix en los catalogos del ecosistema.
# Uso: powershell -ExecutionPolicy Bypass -File .\scripts\icons\refresh-ecosystem-icons.ps1
#
# Prisma        -> assets/icons/nubix (fuente) y public/icons/nubix (servido)
# Aurora Synapse -> public/assets/icons/nubix (generado por scripts/sync-icons.ps1)
#
# Ejecutar despues de `npm run icons:generate`, cuando cambie la fuente canonica.

# Las rutas se resuelven de forma relativa a este script y a la raiz del workspace:
# no hay rutas absolutas al disco local.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workspaceRoot = Split-Path -Parent $repoRoot

# Fuente canonica de Nubix (repo) y original externo (biblioteca).
$repoTransparent = Join-Path $repoRoot 'assets/branding/icons/icon-transparent.png'
$libraryBrand = 'D:/Imágenes/03_Proyectos/02_Development/Icons/Applications/Nubix/Nubix.webp'

# Prisma: catalogo de apps del ecosistema (assets = fuente, public = servido).
$prismaDirs = @(
    (Join-Path $workspaceRoot 'Prisma/assets/icons/nubix'),
    (Join-Path $workspaceRoot 'Prisma/public/icons/nubix')
)
foreach ($dir in $prismaDirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    & magick $libraryBrand -resize 1024x1024 "$dir/icon.png"
    & magick $libraryBrand -quality 92 "$dir/icon.webp"
    Copy-Item $repoTransparent "$dir/icon-transparent.png" -Force
    & magick $repoTransparent -quality 92 "$dir/icon-transparent.webp"
}

# Aurora Synapse: catalogo del launchpad.
$asDir = Join-Path $workspaceRoot 'Aurora-Synapse/public/assets/icons/nubix'
$repoIcon128 = Join-Path $repoRoot 'src-tauri/icons/128x128.png'
New-Item -ItemType Directory -Force -Path $asDir | Out-Null
# El script sync-icons.ps1 usa el 128x128 nativo del repo para icon.webp / icon.png.
& magick $repoIcon128 -quality 92 "$asDir/icon.webp"
Copy-Item $repoIcon128 "$asDir/icon.png" -Force
# Variante transparente (mismo criterio que prisma-upscaler).
& magick $repoTransparent -quality 92 "$asDir/icon-transparent.webp"

Write-Output '--- Prisma assets/icons/nubix ---'
Get-ChildItem $prismaDirs[0] | Select-Object Name, Length | Format-Table -AutoSize
Write-Output '--- Prisma public/icons/nubix ---'
Get-ChildItem $prismaDirs[1] | Select-Object Name, Length | Format-Table -AutoSize
Write-Output '--- Aurora Synapse public/assets/icons/nubix ---'
Get-ChildItem $asDir | Select-Object Name, Length | Format-Table -AutoSize
