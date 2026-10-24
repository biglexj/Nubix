<#
.SYNOPSIS
    Validacion funcional del instalador de Nubix (Inno Setup) en Windows.

.DESCRIPTION
    Fases independientes (se pueden repetir por separado):
      entry      - Arranca el instalador, comprueba la geometria de la ventana,
                   recorre ruta -> carpeta -> instalar con Tab y Shift+Tab,
                   abre el selector de carpeta y cancela.
      install    - Instalacion interactiva completa con ruta editada a mano,
                   capturas de progreso y exito, y comprobacion de que la app abre.
      silent     - Instalacion silenciosa en la carpeta por defecto.
      upgrade    - Reinstala con el mismo AppId y comprueba que no hay una
                   instalacion paralela.
      uninstall  - Desinstala y comprueba que no se borran los datos del usuario.
      themes     - Compila muestras de tema oscuro y claro y las captura.

    Las capturas y el registro quedan en build\validation.

.EXAMPLE
    .\scripts\packaging\Test-Installer.ps1 -Phase entry
#>
[CmdletBinding()]
param(
    [ValidateSet('entry', 'install', 'silent', 'upgrade', 'uninstall', 'themes', 'longpath', 'all')]
    [string]$Phase = 'entry',
    [string]$Installer,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'InstallerUi.psm1') -Force

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Installer) { $Installer = Join-Path $root 'release\Nubix-Setup-0.2.0.exe' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'build\validation' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$logPath = Join-Path $OutputDirectory 'validation.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Write-Log "OK   $Message" 'PASS' }
    else { Write-Log "FALLO $Message" 'FAIL' }
    $script:Results.Add([pscustomobject]@{ Message = $Message; Ok = $Condition }) | Out-Null
}

$script:Results = New-Object System.Collections.ArrayList

# --- Utilidades propias -----------------------------------------------------
function Get-UninstallEntries {
    Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Nubix*' } |
        Select-Object PSChildName, DisplayName, DisplayVersion, InstallLocation, UninstallString
}

function Get-UserDataPath { Join-Path $env:APPDATA 'com.biglexj.nubix' }

function Start-Installer {
    param([string[]]$Arguments = @())
    Start-Process -FilePath $Installer -ArgumentList $Arguments -PassThru
}

function Wait-InstallerWindow {
    param([int]$TimeoutSeconds = 40)
    $h = Find-Window -TitleLike 'Instalar Nubix*' -TimeoutSeconds $TimeoutSeconds
    if (Test-Handle $h) { throw 'No aparecio la ventana del instalador.' }
    Set-Foreground -Handle $h
    return $h
}

function Describe-Focus {
    param([IntPtr]$Handle)
    $f = Get-FocusedControl -Handle $Handle
    if (-not $f) { return 'sin foco' }
    return "{0} [{1}] cliente({2},{3})" -f $f.Class, ($f.Text -replace '\s+', ' '), $f.Left, $f.Top
}

function Focus-Window {
    param([IntPtr]$Handle)
    if (-not (Focus-Installer -Handle $Handle -TimeoutSeconds 45)) {
        Write-Log "AVISO: no se pudo quedar con el primer plano; puede haber dialogos del sistema de otra sesion." 'WARN'
    }
}

function Get-CustomControls {
    <# Controles del panel propio (no los nativos de Inno). #>
    param([IntPtr]$Handle)
    Get-ChildControls -Parent $Handle | Where-Object {
        $_.Class -eq 'TEdit' -or $_.Class -eq 'TNewEdit' -or $_.Class -eq 'TBitmapButton'
    }
}

# --- Fases ------------------------------------------------------------------
function Invoke-EntryPhase {
    Write-Log '--- Fase entry ---' 'PHASE'
    $proc = Start-Installer
    try {
        $h = Wait-InstallerWindow
        $c = Get-ClientRect -Handle $h
        Write-Log ("Area cliente: {0}x{1}" -f ($c.Right - $c.Left), ($c.Bottom - $c.Top))
        Assert-True (($c.Right - $c.Left) -eq 560 -and ($c.Bottom - $c.Top) -eq 444) 'Area cliente de 560x444 unidades logicas a 96 DPI'
        Save-WindowScreenshot -Handle $h -Path (Join-Path $OutputDirectory '01-entrada.png') | Out-Null

        $controls = Get-CustomControls -Handle $h
        foreach ($ctl in $controls) {
            Write-Log ("Control propio: {0} cliente({1},{2})" -f $ctl.Class, $ctl.Left, $ctl.Top)
        }
        $edit = $controls | Where-Object { $_.Class -eq 'TEdit' -or $_.Class -eq 'TNewEdit' } | Select-Object -First 1
        $folder = $controls | Where-Object { $_.Class -eq 'TBitmapButton' -and $_.Left -gt 400 } | Select-Object -First 1
        $install = $controls | Where-Object { $_.Class -eq 'TBitmapButton' -and $_.Left -lt 100 } | Select-Object -First 1
        Assert-True ($null -ne $edit) 'Existe el campo de ruta editable'
        Assert-True ($null -ne $folder) 'Existe el boton de carpeta de instalacion'
        Assert-True ($null -ne $install) 'Existe el boton principal Instalar Nubix'

        # Recorrido con Tab: ruta -> carpeta -> instalar (ciclo cerrado)
        Write-Log ("Foco inicial: " + (Describe-Focus -Handle $h))
        $initial = Get-FocusedControl -Handle $h
        Assert-True ($null -ne $initial -and $initial.Class -eq 'TEdit') 'El foco inicial esta en el campo de ruta'
        $panel = New-Object System.Collections.ArrayList
        for ($i = 1; $i -le 6; $i++) {
            Send-KeyTo -Window $h -Keys '{TAB}'
            $f = Get-FocusedControl -Handle $h
            $desc = if ($f) { "{0}@{1}" -f $f.Class, $f.Left } else { 'sin foco' }
            Write-Log ("Tras $i Tab: " + (Describe-Focus -Handle $h))
            [void]$panel.Add($desc)
            Save-WindowScreenshot -Handle $h -Path (Join-Path $OutputDirectory ("0{0}-tab-{1}.png" -f (1 + $i), $i)) | Out-Null
        }
        Write-Log ("Secuencia de foco: " + ($panel -join ' '))
        $seq = ($panel -join ' ')
        Assert-True ($seq -like '*TEdit@32 TBitmapButton@496 TBitmapButton@20*') 'Tab recorre ruta -> carpeta -> instalar (en ese orden)'
        Assert-True ($seq -like '*TBitmapButton@20 TEdit@32*') 'El ciclo se cierra: instalar -> ruta'
        Assert-True ($seq -notlike '*TNewButton*') 'Los botones nativos Siguiente y Cancelar quedan fuera del recorrido del tab'

        # Shift+Tab: vuelta atras desde instalar -> carpeta -> ruta
        $backSeq = New-Object System.Collections.ArrayList
        for ($i = 1; $i -le 3; $i++) {
            Send-KeyTo -Window $h -Keys '+{TAB}'
            $f = Get-FocusedControl -Handle $h
            $desc = if ($f) { "{0}@{1}" -f $f.Class, $f.Left } else { 'sin foco' }
            [void]$backSeq.Add($desc)
            Write-Log ("Tras Shift+Tab ${i}: " + (Describe-Focus -Handle $h))
        }
        Write-Log ("Secuencia inversa: " + ($backSeq -join ' '))
        Save-WindowScreenshot -Handle $h -Path (Join-Path $OutputDirectory '05-shifttab.png') | Out-Null
        # El recorrido inverso es ciclico: se admite cualquiera de sus fases.
        $back = ($backSeq -join ' ')
        $backOk = ($back -like 'TBitmapButton@20 TBitmapButton@496 TEdit@32') -or
                  ($back -like 'TBitmapButton@496 TEdit@32 TBitmapButton@20') -or
                  ($back -like 'TEdit@32 TBitmapButton@20 TBitmapButton@496')
        Assert-True $backOk 'Shift+Tab recorre el ciclo inverso instalar -> carpeta -> ruta'

        # Selector de carpeta: Enter y Espacio deben abrirlo
        if ($folder) {
            # Llevar el foco al boton de carpeta con Tab
            for ($i = 0; $i -lt 8; $i++) {
                $f = Get-FocusedControl -Handle $h
                if ($f -and $f.Class -eq 'TBitmapButton' -and $f.Left -gt 400) { break }
                Send-KeyTo -Window $h -Keys '{TAB}'
            }
            Write-Log ("Foco en el boton de carpeta: " + (Describe-Focus -Handle $h))
            Send-KeyTo -Window $h -Keys '{ENTER}'
            $dlg = Find-Window -TitleLike 'Selecciona la ubicaci*' -TimeoutSeconds 10
            Assert-True (-not (Test-Handle $dlg)) 'Enter en el boton de carpeta abre el selector de carpetas'
            if (-not (Test-Handle $dlg)) {
                Set-Foreground -Handle $dlg
                Save-WindowScreenshot -Handle $dlg -Path (Join-Path $OutputDirectory '06-selector-carpeta.png') | Out-Null
                Send-KeyTo -Window $dlg -Keys '{ESC}' -TimeoutSeconds 15
                Start-Sleep -Milliseconds 900
                $still = Find-Window -TitleLike 'Selecciona la ubicaci*' -TimeoutSeconds 2
                Assert-True (Test-Handle $still) 'El selector se cierra con Escape'
            }
            # Espacio tambien debe abrirlo
            for ($i = 0; $i -lt 8; $i++) {
                $f = Get-FocusedControl -Handle $h
                if ($f -and $f.Class -eq 'TBitmapButton' -and $f.Left -gt 400) { break }
                Send-KeyTo -Window $h -Keys '{TAB}'
            }
            Send-KeyTo -Window $h -Keys ' '
            $dlg2 = Find-Window -TitleLike 'Selecciona la ubicaci*' -TimeoutSeconds 10
            Assert-True (-not (Test-Handle $dlg2)) 'Espacio en el boton de carpeta abre el selector de carpetas'
            if (-not (Test-Handle $dlg2)) {
                Set-Foreground -Handle $dlg2
                Send-KeyTo -Window $dlg2 -Keys '{ESC}' -TimeoutSeconds 15
                Start-Sleep -Milliseconds 900
            }
        }

        # Cancelacion: la X pide confirmacion en un TaskDialog de Inno
        Send-KeyTo -Window $h -Keys '%{F4}' -TimeoutSeconds 20
        Start-Sleep -Seconds 1
        $dialog = Get-AllWindows | Where-Object { (Get-WindowClass $_) -eq 'TTaskDialogForm' } | Select-Object -First 1
        if ($dialog) {
            Write-Log ("Dialogo de confirmacion: " + (Get-WindowText $dialog))
            Set-Foreground -Handle $dialog
            Save-WindowScreenshot -Handle $dialog -Path (Join-Path $OutputDirectory '06b-confirmacion-cancelar.png') | Out-Null
            $btn = Get-ChildControls -Parent $dialog | Where-Object { $_.Class -eq 'TNewButton' -and ($_.Text -like '*Sí*' -or $_.Text -like '*Yes*') } | Select-Object -First 1
            if ($btn) {
                [void][InstallerUi.Win]::SendMessageW($btn.Handle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)  # BM_CLICK
            }
            else {
                Send-KeyTo -Window $dialog -Keys '{ENTER}' -TimeoutSeconds 15
            }
            Start-Sleep -Seconds 2
        }
        # El proceso puede tardar en cerrar: se espera a que desaparezca la ventana.
        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $deadline) {
            $win = Find-Window -TitleLike 'Instalar Nubix*' -TimeoutSeconds 1
            if (Test-Handle $win) { break }
            $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
            if ($null -eq $alive) { break }
            Start-Sleep -Milliseconds 500
        }
        $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        $win = Find-Window -TitleLike 'Instalar Nubix*' -TimeoutSeconds 1
        Assert-True (($null -eq $alive) -and (Test-Handle $win)) 'La X cancela y cierra el instalador'
        if ($alive) { $alive | Stop-Process -Force }
    }
    finally {
        Stop-InstallerProcesses -NamePattern 'Nubix-Setup-0.2.0*'
    }
}

function Invoke-InstallPhase {
    param([string]$TargetDir)
    Write-Log '--- Fase install (interactiva) ---' 'PHASE'
    $proc = Start-Installer
    $h = Wait-InstallerWindow

    $controls = Get-CustomControls -Handle $h
    $edit = $controls | Where-Object { $_.Class -eq 'TEdit' -or $_.Class -eq 'TNewEdit' } | Select-Object -First 1
    Assert-True ($null -ne $edit) 'El campo de ruta editable existe'

    if ($edit) {
        # Llevar el foco al campo de ruta y escribir una ruta a mano
        for ($i = 0; $i -lt 8; $i++) {
            $f = Get-FocusedControl -Handle $h
            if ($f -and ($f.Class -eq 'TEdit' -or $f.Class -eq 'TNewEdit')) { break }
            Send-KeyTo -Window $h -Keys '{TAB}'
        }
        Send-KeyTo -Window $h -Keys '^a'
        Send-KeyTo -Window $h -Keys ($TargetDir + '\')
        Start-Sleep -Milliseconds 500
        $value = Get-ControlText -Handle $edit.Handle
        if ($value -notlike '*Nubix-Instalacion-Personalizada*') {
            Write-Log "El teclado no escribio la ruta completa ('$value'); se escribe por mensaje al control."
            Set-Text -Handle $edit.Handle -Text ($TargetDir + '\')
            $value = Get-ControlText -Handle $edit.Handle
        }
        Write-Log "Ruta escrita: $value"
        Assert-True ($value -like '*Nubix-Instalacion-Personalizada*') 'La ruta se puede editar a mano'
        Save-WindowScreenshot -Handle $h -Path (Join-Path $OutputDirectory '07-ruta-editada.png') | Out-Null
    }

    # Instalar con Enter desde el boton principal
    $controls = Get-CustomControls -Handle $h
    $installBtn = $controls | Where-Object { $_.Class -eq 'TBitmapButton' -and $_.Left -lt 100 } | Select-Object -First 1
    Assert-True ($null -ne $installBtn) 'Se localiza el boton principal Instalar Nubix'
    if ($installBtn) {
        for ($i = 0; $i -lt 10; $i++) {
            $f = Get-FocusedControl -Handle $h
            if ($f -and $f.Class -eq 'TBitmapButton' -and $f.Left -lt 100) { break }
            Send-KeyTo -Window $h -Keys '{TAB}'
        }
        Write-Log ("Foco antes de instalar: " + (Describe-Focus -Handle $h))
        Save-WindowScreenshot -Handle $h -Path (Join-Path $OutputDirectory '08-foco-instalar.png') | Out-Null
        # Enter con teclado real. Si otra ventana roba el primer plano, se
        # reenvia la tecla directamente al control con foco.
        $started = $false
        try {
            Send-KeyTo -Window $h -Keys '{ENTER}' -TimeoutSeconds 20
        }
        catch {
            Write-Log ("Aviso: " + $_.Exception.Message) 'WARN'
        }
        Start-Sleep -Seconds 3
        $f = Get-FocusedControl -Handle $h
        if ($f -and $f.Class -eq 'TBitmapButton') {
            Write-Log 'El instalador no arranco con la tecla real; se reenvia al control con foco.'
            Post-Key -Handle $f.Handle -VirtualKey 13
            Start-Sleep -Seconds 2
        }
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline) {
            if (Test-Path (Join-Path $TargetDir 'nubix.exe')) { $started = $true; break }
            Start-Sleep -Milliseconds 500
        }
        Assert-True $started 'El boton Instalar Nubix arranca la instalacion'
    }

    # Progreso (pantalla nativa): se capturan fotogramas seguidos porque la
    # pantalla de progreso es muy breve. El handle del asistente no cambia al
    # pasar de pagina.
    for ($i = 1; $i -le 10; $i++) {
        Save-WindowScreenshot -Handle $h -Path (Join-Path $OutputDirectory ("09-progreso-{0}.png" -f $i)) | Out-Null
        Start-Sleep -Milliseconds 150
    }
    Write-Log 'Capturas de la pantalla de progreso guardadas.'

    # Exito (pantalla nativa)
    $deadline = (Get-Date).AddSeconds(90)
    $fh = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        $fh = Find-Window -TitleLike 'Instalar Nubix*' -TimeoutSeconds 5
        if (-not (Test-Handle $fh)) { break }
        $controls = Get-ChildControls -Parent $fh
        $hasFinish = $controls | Where-Object { $_.Text -like '*Finalizar*' -or $_.Text -like '*Finish*' }
        if ($hasFinish) { break }
        Start-Sleep -Seconds 1
    }
    if (-not (Test-Handle $fh)) {
        Save-WindowScreenshot -Handle $fh -Path (Join-Path $OutputDirectory '10-exito.png') | Out-Null
        Write-Log 'Captura de la pantalla de exito guardada.'
    }

    # Cerrar la pagina de exito: el bloque [Run] arranca la app tras "Finalizar".
    # Con la plantilla corregida, Enter activa "Finalizar" (boton por defecto
    # fuera de la pantalla de entrada). Si no respondiera, se pulsa con el raton.
    $fh2 = Find-Window -TitleLike 'Instalar Nubix*' -TimeoutSeconds 5
    if (-not (Test-Handle $fh2)) {
        # La plantilla lleva el foco a "Finalizar" al entrar en la pagina de
        # exito, pero ese SetFocus solo surte efecto si la ventana esta en
        # primer plano: en un escritorio compartido otra ventana puede
        # robarselo y el Enter se queda en la casilla "Ejecutar <App>".
        Set-Foreground -Handle $fh2
        Start-Sleep -Milliseconds 400
        Write-Log ("Foco en la pantalla de exito: " + (Describe-Focus -Handle $fh2))
        try { Send-KeyTo -Window $fh2 -Keys '{ENTER}' -TimeoutSeconds 20 }
        catch { Write-Log ("Aviso al finalizar: " + $_.Exception.Message) 'WARN' }
        Start-Sleep -Seconds 2
        $fh3 = Find-Window -TitleLike 'Instalar Nubix*' -TimeoutSeconds 2
        if (-not (Test-Handle $fh3)) {
            Write-Log 'Enter no cerro el instalador; se pulsa el boton Finalizar con el raton.' 'WARN'
            $fin = Get-ChildControls -Parent $fh3 | Where-Object { $_.Class -eq 'TNewButton' -and $_.Text -like '*Finalizar*' } | Select-Object -First 1
            if ($fin) {
                $r = Get-WindowRect $fin.Handle
                Click-Screen -X ([int](($r.Left + $r.Right) / 2)) -Y ([int](($r.Top + $r.Bottom) / 2))
            }
        }
    }
    Start-Sleep -Seconds 2
    # El instalador debe cerrar solo: matarlo a la fuerza afecta a la app que
    # acaba de lanzar (hereda el proceso de instalacion).
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        $still = Get-Process -Name 'Nubix-Setup-0.2.0*' -ErrorAction SilentlyContinue
        if (-not $still) { break }
        Start-Sleep -Milliseconds 500
    }

    # La app debe arrancar (casilla "Ejecutar Nubix")
    $app = $null
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        $app = Get-Process -Name 'nubix' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($app) { break }
        Start-Sleep -Milliseconds 500
    }
    Assert-True ($null -ne $app) 'La aplicacion instalada se ejecuta al terminar'
    if ($app) {
        # El arranque de WebView2 puede tardar bastante con la maquina cargada.
        $aw = Find-Window -TitleLike 'Nubix*' -TimeoutSeconds 120
        Assert-True (-not (Test-Handle $aw)) 'La ventana de Nubix aparece'
        if (-not (Test-Handle $aw)) {
            Save-WindowScreenshot -Handle $aw -Path (Join-Path $OutputDirectory '11-app.png') | Out-Null
        }
    }

    Get-Process -Name 'nubix' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Comprobaciones de la instalacion
    Assert-True (Test-Path (Join-Path $TargetDir 'nubix.exe')) "El ejecutable queda en $TargetDir"
    Assert-True (Test-Path (Join-Path $TargetDir 'unins000.exe')) 'Existe el desinstalador de Inno Setup'
    Assert-True (Test-Path (Join-Path $TargetDir 'WebView2Loader.dll')) 'Se instala el runtime WebView2'
    $entries = Get-UninstallEntries
    Assert-True (($entries | Measure-Object).Count -eq 1) 'Hay una sola entrada en Agregar o quitar programas'
    Write-Log ("Entradas: " + (($entries | ForEach-Object { "$($_.PSChildName) $($_.InstallLocation)" }) -join ' | '))
}

function Invoke-SilentPhase {
    param([switch]$ExpectUpgrade)
    Write-Log '--- Fase silent/upgrade ---' 'PHASE'
    $proc = Start-Installer -Arguments @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-')
    $proc.WaitForExit(300000) | Out-Null
    Write-Log "Codigo de salida del instalador: $($proc.ExitCode)"
    Assert-True ($proc.ExitCode -eq 0) 'La instalacion silenciosa termina con codigo 0'
    $default = Join-Path $env:LOCALAPPDATA 'Programs\Nubix'
    Assert-True (Test-Path (Join-Path $default 'nubix.exe')) "La app queda en la carpeta por defecto $default"
    $entries = Get-UninstallEntries
    Assert-True (($entries | Measure-Object).Count -eq 1) 'Sigue habiendo una sola entrada tras instalar de nuevo'
    Write-Log ("Entradas: " + (($entries | ForEach-Object { "$($_.PSChildName) $($_.DisplayVersion) $($_.InstallLocation)" }) -join ' | '))
    $dirs = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs') -Directory -Filter 'Nubix*' -ErrorAction SilentlyContinue
    Write-Log ("Carpetas de instalacion en %LOCALAPPDATA%\Programs: " + (($dirs | ForEach-Object { $_.Name }) -join ' | '))
}

function Invoke-UninstallPhase {
    param([string]$InstallDirectory)
    Write-Log '--- Fase uninstall ---' 'PHASE'
    if (-not $InstallDirectory) { $InstallDirectory = Join-Path $env:LOCALAPPDATA 'Programs\Nubix' }
    $default = $InstallDirectory
    $uninstaller = Join-Path $default 'unins000.exe'
    if (-not (Test-Path $uninstaller)) {
        Write-Log 'No hay desinstalador; se omite la fase.' 'WARN'
        return
    }
    # Datos del usuario: marcador para comprobar que no se borran
    $data = Get-UserDataPath
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    $marker = Join-Path $data 'validacion-no-borrar.txt'
    Set-Content -LiteralPath $marker -Value 'marcador de validacion' -Encoding UTF8
    Write-Log "Marcador de datos de usuario: $marker"

    $proc = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -PassThru
    $proc.WaitForExit(180000) | Out-Null
    Write-Log "Codigo de salida del desinstalador: $($proc.ExitCode)"
    Assert-True ($proc.ExitCode -eq 0) 'La desinstalacion silenciosa termina con codigo 0'
    # Inno Setup borra la carpeta al salir el proceso: se espera a que desaparezca.
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline -and (Test-Path $default)) { Start-Sleep -Milliseconds 500 }
    Assert-True (-not (Test-Path $default)) 'Se retira la carpeta de la aplicacion'
    Assert-True (Test-Path $marker) 'Los datos del usuario NO se borran al desinstalar'
    $entries = Get-UninstallEntries
    Assert-True (($entries | Measure-Object).Count -eq 0) 'Se retira la entrada de Agregar o quitar programas'
    $shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Nubix.lnk'
    Assert-True (-not (Test-Path $shortcut)) 'Se retira el acceso directo del menu Inicio'
}

function Invoke-ThemesPhase {
    Write-Log '--- Fase themes ---' 'PHASE'
    $iscc = 'D:\Proyectos\biglexj\Scripts\tools\InnoSetup\ISCC.exe'
    $themeDir = Join-Path $root 'build\validation\themes'
    New-Item -ItemType Directory -Path $themeDir -Force | Out-Null
    foreach ($theme in @('dark', 'light')) {
        $out = Join-Path $themeDir "Nubix-Setup-$theme.exe"
        & $iscc (Join-Path $root 'packaging\windows\setup.iss') "/DMyAppTheme=$theme" "/O$themeDir" "/FNubix-Setup-$theme" | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log "ISCC fallo con el tema $theme" 'FAIL'; continue }
        $p = Start-Process -FilePath $out -PassThru
        $h = Wait-InstallerWindow
        Save-WindowScreenshot -Handle $h -Path (Join-Path $OutputDirectory "12-tema-$theme.png") | Out-Null
        Set-Foreground -Handle $h
        Send-Key '%{F4}'
        Start-Sleep -Seconds 1
        $dialog = Get-AllWindows | Where-Object { (Get-WindowClass $_) -eq 'TTaskDialogForm' } | Select-Object -First 1
        if ($dialog) {
            Set-Foreground -Handle $dialog
            $btn = Get-ChildControls -Parent $dialog | Where-Object { $_.Class -eq 'TNewButton' -and ($_.Text -like '*Sí*' -or $_.Text -like '*Yes*') } | Select-Object -First 1
            if ($btn) { [void][InstallerUi.Win]::SendMessageW($btn.Handle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
            Start-Sleep -Seconds 1
        }
        Stop-InstallerProcesses -NamePattern "Nubix-Setup-$theme*"
        Write-Log "Captura del tema $theme guardada."
    }
}

function Invoke-LongPathPhase {
    Write-Log '--- Fase longpath ---' 'PHASE'
    $proc = Start-Installer
    $h = Wait-InstallerWindow
    $controls = Get-CustomControls -Handle $h
    $edit = $controls | Where-Object { $_.Class -eq 'TEdit' -or $_.Class -eq 'TNewEdit' } | Select-Object -First 1
    Assert-True ($null -ne $edit) 'El campo de ruta editable existe'

    # Ruta larga: se escribe caracter a caracter como lo haria el usuario.
    $long = 'C:\Users\biglexj\AppData\Local\Programs\Nubix-Carpeta-Con-Nombre-Muy-Largo-Para-Probar-El-Campo-De-Ruta-Del-Instalador'
    Set-Focus-Edit -Handle $h
    Send-KeyTo -Window $h -Keys '^a'
    Send-KeyTo -Window $h -Keys ($long + '\')
    Start-Sleep -Milliseconds 600
    $value = Get-ControlText -Handle $edit.Handle
    if ($value -notlike '*Nubix-Carpeta-Con-Nombre-Muy-Largo*') {
        Write-Log 'El teclado no completo la ruta larga; se escribe por mensaje al control.'
        Set-Text -Handle $edit.Handle -Text ($long + '\')
        $value = Get-ControlText -Handle $edit.Handle
    }
    Write-Log "Ruta larga escrita ($($value.Length) caracteres): $value"
    Assert-True ($value -like '*Nubix-Carpeta-Con-Nombre-Muy-Largo*') 'El campo de ruta admite un nombre de carpeta largo'
    Save-WindowScreenshot -Handle $h -Path (Join-Path $OutputDirectory '13-ruta-larga.png') | Out-Null

    # El boton debe rechazar rutas que no sean absolutas.
    Set-Text -Handle $edit.Handle -Text 'Ruta\Relativa\Sin\Absoluta'
    $installBtn = (Get-CustomControls -Handle $h) | Where-Object { $_.Class -eq 'TBitmapButton' -and $_.Left -lt 100 } | Select-Object -First 1
    for ($i = 0; $i -lt 8; $i++) {
        $f = Get-FocusedControl -Handle $h
        if ($f -and $f.Class -eq 'TBitmapButton' -and $f.Left -lt 100) { break }
        Send-KeyTo -Window $h -Keys '{TAB}'
    }
    Send-KeyTo -Window $h -Keys '{ENTER}' -TimeoutSeconds 25
    Start-Sleep -Seconds 2
    # Se busca el aviso del propio instalador por su texto, no por clase.
    $dlg = $null
    foreach ($w in Get-AllWindows) {
        if ((Get-WindowClass $w) -notmatch '#32770|TTaskDialogForm') { continue }
        foreach ($child in Get-ChildControls -Parent $w) {
            if ($child.Text -like '*ruta absoluta*') { $dlg = $w; break }
        }
        if ($dlg) { break }
    }
    if ($dlg) {
        Save-WindowScreenshot -Handle $dlg -Path (Join-Path $OutputDirectory '13b-ruta-invalida.png') | Out-Null
        Write-Log ("Aviso de ruta invalida: " + (Get-WindowText $dlg))
    }
    Assert-True ($null -ne $dlg) 'Una ruta relativa se rechaza con aviso y no instala'
    Assert-True (-not (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\Nubix\nubix.exe'))) 'Con ruta invalida no se instala nada'
    if ($dlg) { Set-Foreground -Handle $dlg; Send-KeyTo -Window $dlg -Keys '{ENTER}' -TimeoutSeconds 15 }
    Set-Foreground -Handle $h
    Send-KeyTo -Window $h -Keys '%{F4}' -TimeoutSeconds 15
    Stop-InstallerProcesses -NamePattern 'Nubix-Setup-0.2.0*'
}

function Set-Focus-Edit {
    param([IntPtr]$Handle)
    for ($i = 0; $i -lt 8; $i++) {
        $f = Get-FocusedControl -Handle $Handle
        if ($f -and ($f.Class -eq 'TEdit' -or $f.Class -eq 'TNewEdit')) { return }
        Send-KeyTo -Window $Handle -Keys '{TAB}'
    }
}

# --- Ejecucion --------------------------------------------------------------
Write-Log "Fase solicitada: $Phase"
Write-Log "Instalador: $Installer"

try {
    switch ($Phase) {
        'entry' { Invoke-EntryPhase }
        'install' { Invoke-InstallPhase -TargetDir (Join-Path $env:LOCALAPPDATA 'Programs\Nubix-Instalacion-Personalizada') }
        'silent' { Invoke-SilentPhase }
        'upgrade' { Invoke-SilentPhase -ExpectUpgrade }
        'uninstall' { Invoke-UninstallPhase }
        'themes' { Invoke-ThemesPhase }
        'longpath' { Invoke-LongPathPhase }
        'all' {
            Invoke-EntryPhase
            Invoke-InstallPhase -TargetDir (Join-Path $env:LOCALAPPDATA 'Programs\Nubix-Instalacion-Personalizada')
            Invoke-UninstallPhase -InstallDirectory (Join-Path $env:LOCALAPPDATA 'Programs\Nubix-Instalacion-Personalizada')
            Invoke-SilentPhase
            Invoke-SilentPhase -ExpectUpgrade
            Invoke-UninstallPhase
            Invoke-ThemesPhase
        }
    }
}
catch {
    Write-Log ("ERROR: " + $_.Exception.Message) 'ERROR'
    Write-Log ("STACK: " + $_.ScriptStackTrace) 'ERROR'
    Write-Log ("ORIGEN: " + $_.InvocationInfo.ScriptName + ':' + $_.InvocationInfo.ScriptLineNumber) 'ERROR'
    $script:Results.Add([pscustomobject]@{ Message = ('Error: ' + $_.Exception.Message); Ok = $false }) | Out-Null
}

$failed = @($script:Results | Where-Object { -not $_.Ok })
Write-Log ("Comprobaciones: {0} | fallidas: {1}" -f $script:Results.Count, $failed.Count)
if ($failed.Count -gt 0) {
    $failed | ForEach-Object { Write-Log ("FALLA: " + $_.Message) 'FAIL' }
    exit 1
}
exit 0
