<#
.SYNOPSIS
    Mide por pixeles el centrado del icono de Nubix en el instalador.

.DESCRIPTION
    Mide el glifo real (pixels que se diferencian del fondo) dentro de:

      - la caja del logo: 64 x 64 en cliente (248,96), con el icono de 40 x 40
        en (260,108);
      - el icono de la cabecera: 20 x 20 en cliente (20,19).

    Devuelve la caja del glifo y el descentrado respecto al centro ideal de su
    recuadro (0 = centrado). Sirve para comparar el antes y el despues de una
    correccion de la plantilla.

    El desplazamiento del area cliente dentro de la captura se calcula a partir
    de la ventana real, o se puede pasar a mano con -OffsetX/-OffsetY.

.EXAMPLE
    .\scripts\packaging\Measure-Icon.ps1 -Image .\build\validation\01-entrada.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Image,
    [int]$OffsetX = 8,
    [int]$OffsetY = 31,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Get-Pixel {
    param($Bmp, [int]$X, [int]$Y)
    return $Bmp.GetPixel($X, $Y)
}

function Measure-Glyph {
    param($Bmp, [int]$BoxX, [int]$BoxY, [int]$BoxW, [int]$BoxH, $BgColor, [int]$Threshold = 26)
    $minX = 9999; $minY = 9999; $maxX = -1; $maxY = -1
    for ($y = $BoxY; $y -lt ($BoxY + $BoxH); $y++) {
        for ($x = $BoxX; $x -lt ($BoxX + $BoxW); $x++) {
            $p = Get-Pixel $Bmp $x $y
            $dr = [Math]::Abs($p.R - $BgColor.R)
            $dg = [Math]::Abs($p.G - $BgColor.G)
            $db = [Math]::Abs($p.B - $BgColor.B)
            if (($dr + $dg + $db) -gt $Threshold) {
                if ($x -lt $minX) { $minX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    if ($maxX -lt 0) { return $null }
    $w = $maxX - $minX + 1
    $h = $maxY - $minY + 1
    $idealX = [int][Math]::Floor(($BoxW - $w) / 2)
    $idealY = [int][Math]::Floor(($BoxH - $h) / 2)
    return [pscustomobject]@{
        GlyphX = $minX - $BoxX
        GlyphY = $minY - $BoxY
        Width = $w
        Height = $h
        IdealX = $idealX
        IdealY = $idealY
        OffsetX = ($minX - $BoxX) - $idealX
        OffsetY = ($minY - $BoxY) - $idealY
    }
}

$bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Image).Path)
try {
    # Fondos de referencia, tomados de la propia captura
    $bgPanel = Get-Pixel $bmp ($OffsetX + 10) ($OffsetY + 200)
    $bgContainer = Get-Pixel $bmp ($OffsetX + 250) ($OffsetY + 128)

    $logo = Measure-Glyph -Bmp $bmp -BoxX ($OffsetX + 260) -BoxY ($OffsetY + 108) -BoxW 40 -BoxH 40 -BgColor $bgContainer
    $header = Measure-Glyph -Bmp $bmp -BoxX ($OffsetX + 20) -BoxY ($OffsetY + 19) -BoxW 20 -BoxH 20 -BgColor $bgPanel

    $result = [pscustomobject]@{
        Image = (Split-Path -Leaf $Image)
        Size = "$($bmp.Width)x$($bmp.Height)"
        Offset = "$OffsetX,$OffsetY"
        LogoGlyph = if ($logo) { "$($logo.Width)x$($logo.Height) en ($($logo.GlyphX),$($logo.GlyphY))" } else { 'n/d' }
        LogoOffset = if ($logo) { "dx=$($logo.OffsetX) dy=$($logo.OffsetY)" } else { 'n/d' }
        HeaderGlyph = if ($header) { "$($header.Width)x$($header.Height) en ($($header.GlyphX),$($header.GlyphY))" } else { 'n/d' }
        HeaderOffset = if ($header) { "dx=$($header.OffsetX) dy=$($header.OffsetY)" } else { 'n/d' }
    }
    if (-not $Quiet) {
        Write-Host "Imagen: $($result.Image) ($($result.Size))"
        Write-Host "  Caja del logo 64x64, icono 40x40 -> glifo $($result.LogoGlyph), descentrado $($result.LogoOffset)"
        Write-Host "  Icono de cabecera 20x20        -> glifo $($result.HeaderGlyph), descentrado $($result.HeaderOffset)"
    }
    $result
}
finally {
    $bmp.Dispose()
}
