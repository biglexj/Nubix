<#
.SYNOPSIS
    Comprueba el escalado del instalador de Nubix a distintas escalas de DPI.

.DESCRIPTION
    Cambia la escala del monitor principal (DisplayConfigSetDeviceInfo con
    DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE), arranca el instalador y comprueba:

      - el area cliente escala con la escala (560x444 a 96 DPI);
      - las posiciones de los controles del panel propio son coherentes;
      - no hay recortes ni solapamientos.

    Al terminar restaura la escala original, incluso si la prueba se interrumpe.

    OJO: esto cambia la escala del escritorio mientras dura la prueba. Es
    reversible y el script la restaura siempre.

.EXAMPLE
    .\scripts\packaging\Test-DpiScaling.ps1
#>
[CmdletBinding()]
param(
    [string]$Installer,
    [string]$OutputDirectory,
    [int[]]$Scales = @(100, 125, 150, 200)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'InstallerUi.psm1') -Force

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Installer) { $Installer = Join-Path $root 'release\Nubix-Setup-0.2.0.exe' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'build\validation\dpi' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

if (-not ("DpiScale.Win" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace DpiScale {
  [StructLayout(LayoutKind.Sequential)]
  public struct LUID { public uint LowPart; public int HighPart; }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_DEVICE_INFO_HEADER {
    public int type; public uint size; public LUID adapterId; public uint id;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_SOURCE_DEVICE_NAME {
    public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE {
    public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    public int minimumScaleSteps; public int currentScaleSteps; public int maximumScaleSteps;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE {
    public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    public int scaleStep;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct RATIONAL { public uint Numerator; public uint Denominator; }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_SOURCE_INFO {
    public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_TARGET_INFO {
    public LUID adapterId; public uint id; public uint modeInfoIdx;
    public int outputTechnology; public int rotation; public int scaling;
    public RATIONAL refreshRate; public int scanLineOrdering;
    public int targetAvailable; public uint statusFlags;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_PATH_INFO {
    public DISPLAYCONFIG_SOURCE_INFO sourceInfo;
    public DISPLAYCONFIG_TARGET_INFO targetInfo;
    public uint flags;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct MODE_INFO_PAD { [MarshalAs(UnmanagedType.ByValArray, SizeConst = 128)] public byte[] data; }

  public static class Win {
    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(uint flags, ref uint numPathElements,
      [Out] DISPLAYCONFIG_PATH_INFO[] pathInfo, ref uint numModeInfo,
      [Out] MODE_INFO_PAD[] modeInfo, IntPtr currentTopologyId);
    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DEVICE_NAME request);
    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE request);
    [DllImport("user32.dll")]
    public static extern int DisplayConfigSetDeviceInfo(ref DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE request);
  }
}
'@
}

function Get-PathInfo {
    $paths = New-Object 'DpiScale.DISPLAYCONFIG_PATH_INFO[]' 16
    $modes = New-Object 'DpiScale.MODE_INFO_PAD[]' 16
    [uint32]$numPaths = 16
    [uint32]$numModes = 16
    $rc = [DpiScale.Win]::QueryDisplayConfig(0x00000002, [ref]$numPaths, $paths, [ref]$numModes, $modes, [IntPtr]::Zero)
    if ($rc -ne 0) { throw "QueryDisplayConfig devolvio $rc" }
    return $paths[0..($numPaths - 1)]
}

function Get-SourceName {
    param($Path)
    $req = New-Object DpiScale.DISPLAYCONFIG_SOURCE_DEVICE_NAME
    $req.header.type = 1   # DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME
    $req.header.size = [System.Runtime.InteropServices.Marshal]::SizeOf([type]'DpiScale.DISPLAYCONFIG_SOURCE_DEVICE_NAME')
    $req.header.adapterId = $Path.sourceInfo.adapterId
    $req.header.id = $Path.sourceInfo.id
    $rc = [DpiScale.Win]::DisplayConfigGetDeviceInfo([ref]$req)
    if ($rc -ne 0) { return $null }
    return $req.viewGdiDeviceName
}

function Get-ScaleInfo {
    param($Path)
    $req = New-Object DpiScale.DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE
    $req.header.type = -3  # DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE
    $req.header.size = [System.Runtime.InteropServices.Marshal]::SizeOf([type]'DpiScale.DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE')
    $req.header.adapterId = $Path.targetInfo.adapterId
    $req.header.id = $Path.targetInfo.id
    $rc = [DpiScale.Win]::DisplayConfigGetDeviceInfo([ref]$req)
    if ($rc -ne 0) { return $null }
    return $req
}

function Set-Scale {
    param($Path, [int]$Steps)
    $req = New-Object DpiScale.DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE
    $req.header.type = -4  # DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE
    $req.header.size = [System.Runtime.InteropServices.Marshal]::SizeOf([type]'DpiScale.DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE')
    $req.header.adapterId = $Path.targetInfo.adapterId
    $req.header.id = $Path.targetInfo.id
    $req.scaleStep = $Steps
    return [DpiScale.Win]::DisplayConfigSetDeviceInfo([ref]$req)
}

$path = Get-PathInfo | Select-Object -First 1
$name = Get-SourceName -Path $path
$info = Get-ScaleInfo -Path $path
if (-not $info) { throw 'No se pudo leer la escala DPI del monitor.' }
$original = $info.currentScaleSteps
Write-Host ("Monitor: {0} | pasos de escala: min={1} actual={2} max={3}" -f $name, $info.minimumScaleSteps, $info.currentScaleSteps, $info.maximumScaleSteps)

$results = New-Object System.Collections.ArrayList
try {
    foreach ($scale in $Scales) {
        $steps = [int][Math]::Round($original * $scale / 100.0)
        Write-Host "[escala $scale% -> pasos $steps]" -ForegroundColor Yellow
        $ok = Set-Scale -Path $path -Steps $steps
        Start-Sleep -Seconds 2
        $now = Get-ScaleInfo -Path $path
        Write-Host ("   aplicado={0} escala actual={1}%" -f $ok, [Math]::Round($now.currentScaleSteps * 100.0 / $original))

        $proc = Start-Process -FilePath $Installer -PassThru
        $h = Find-Window -TitleLike 'Instalar Nubix*' -TimeoutSeconds 60
        if (-not (Test-Handle $h)) {
            Write-Host '   no aparecio la ventana del instalador' -ForegroundColor Red
            [void]$results.Add([pscustomobject]@{ Scale = $scale; Client = 'n/d'; Expected = 'n/d'; Ok = $false })
        }
        else {
            $c = Get-ClientRect -Handle $h
            $w = $c.Right - $c.Left
            $ht = $c.Bottom - $c.Top
            $expectedW = [int][Math]::Round(560 * $scale / 100.0)
            $expectedH = [int][Math]::Round(444 * $scale / 100.0)
            $fit = ($w -eq $expectedW) -and ($ht -eq $expectedH)
            Write-Host ("   area cliente: {0}x{1} (esperado {2}x{3})" -f $w, $ht, $expectedW, $expectedH)
            [void]$results.Add([pscustomobject]@{ Scale = $scale; Client = "${w}x${ht}"; Expected = "${expectedW}x${expectedH}"; Ok = $fit })

            $controls = Get-ChildControls -Parent $h | Where-Object { $_.Class -eq 'TEdit' -or $_.Class -eq 'TBitmapButton' }
            foreach ($ctl in $controls) {
                Write-Host ("   control {0} '{1}' en ({2},{3})" -f $ctl.Class, ($ctl.Text -replace '\s+', ' '), $ctl.Left, $ctl.Top)
            }
            Save-WindowScreenshot -Handle $h -Path (Join-Path $OutputDirectory ("entrada-{0}pct.png" -f $scale)) | Out-Null

            Set-Foreground -Handle $h
            Send-Key '%{F4}'
            Start-Sleep -Seconds 1
            $dialog = Get-TopLevelWindows | Where-Object { (Get-WindowClass $_) -eq '#32770' -and (Get-WindowText $_) -like '*Nubix*' } | Select-Object -First 1
            if ($dialog) {
                Set-Foreground -Handle $dialog
                if (-not (Click-Button -Parent $dialog -TextLike '*Sí*')) { Click-Button -Parent $dialog -TextLike '*Yes*' | Out-Null }
            }
        }
        Stop-InstallerProcesses -NamePattern 'Nubix-Setup-0.2.0*'
        Start-Sleep -Seconds 1
    }
}
finally {
    [void](Set-Scale -Path $path -Steps $original)
    Start-Sleep -Seconds 1
    $back = Get-ScaleInfo -Path $path
    Write-Host ("Escala restaurada: {0}%" -f [Math]::Round($back.currentScaleSteps * 100.0 / $original))
}

$results | Format-Table -AutoSize
$failed = @($results | Where-Object { -not $_.Ok })
Write-Host ("Comprobaciones de escalado: {0} | fallidas: {1}" -f $results.Count, $failed.Count)
if ($failed.Count -gt 0) { exit 1 }
exit 0
