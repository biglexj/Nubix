$ErrorActionPreference = 'Stop'

# Refresca los iconos de Nubix en los catalogos del ecosistema.
# Uso: powershell -ExecutionPolicy Bypass -File .\scripts\icons\refresh-ecosystem-icons.ps1
#
# Prisma        -> assets/icons/nubix (fuente) y public/icons/nubix (servido)
# Aurora Synapse -> public/assets/icons/nubix (generado por scripts/sync-icons.ps1)
#
# Ejecutar despues de `npm run icons:generate`, cuando cambie la fuente canonica.

# Fuente canonica de Nubix (repo) y original externo (biblioteca).
$repoTransparent = 'D:/Proyectos/biglexj/Nubix/assets/branding/icons/icon-transparent.png'
$libraryBrand = 'D:/Imágenes/03_Proyectos/02_Development/Icons/Applications/Nubix/Nubix.webp'

# Prisma: catalogo de apps del ecosistema (assets = fuente, public = servido).
foreach ($dir in @(
    'D:/Proyectos/biglexj/Prisma/assets/icons/nubix',
    'D:/Proyectos/biglexj/Prisma/public/icons/nubix'
)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    & magick $libraryBrand -resize 1024x1024 "$dir/icon.png"
    & magick $libraryBrand -quality 92 "$dir/icon.webp"
    Copy-Item $repoTransparent "$dir/icon-transparent.png" -Force
    & magick $repoTransparent -quality 92 "$dir/icon-transparent.webp"
}

# Aurora Synapse: catalogo del launchpad.
$asDir = 'D:/Proyectos/biglexj/Aurora-Synapse/public/assets/icons/nubix'
New-Item -ItemType Directory -Force -Path $asDir | Out-Null
# El script sync-icons.ps1 usa el 128x128 nativo del repo para icon.webp / icon.png.
& magick 'D:/Proyectos/biglexj/Nubix/src-tauri/icons/128x128.png' -quality 92 "$asDir/icon.webp"
Copy-Item 'D:/Proyectos/biglexj/Nubix/src-tauri/icons/128x128.png' "$asDir/icon.png" -Force
# Variante transparente (mismo criterio que prisma-upscaler).
& magick $repoTransparent -quality 92 "$asDir/icon-transparent.webp"

Write-Output '--- Prisma assets/icons/nubix ---'
Get-ChildItem 'D:/Proyectos/biglexj/Prisma/assets/icons/nubix' | Select-Object Name, Length | Format-Table -AutoSize
Write-Output '--- Prisma public/icons/nubix ---'
Get-ChildItem 'D:/Proyectos/biglexj/Prisma/public/icons/nubix' | Select-Object Name, Length | Format-Table -AutoSize
Write-Output '--- Aurora Synapse public/assets/icons/nubix ---'
Get-ChildItem $asDir | Select-Object Name, Length | Format-Table -AutoSize
