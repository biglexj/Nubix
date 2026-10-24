<#
.SYNOPSIS
    Utilidades de bajo nivel para validar el instalador de Nubix en Windows.

.DESCRIPTION
    Solo para validacion local: localizar ventanas, capturarlas a PNG, enviar
    teclado y leer que control tiene el foco. No forma parte del instalador.

    Uso:  Import-Module .\InstallerUi.psm1
#>

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

if (-not ("InstallerUi.Win" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace InstallerUi {
  public static class Win {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct GUITHREADINFO {
      public int cbSize;
      public uint flags;
      public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
      public RECT rcCaret;
    }

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId")] public static extern uint GetWindowPid(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO gti);
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr wp, string lp);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr wp, StringBuilder lp);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  }
}
'@
}

function Get-WindowText {
    param([IntPtr]$Handle)
    $sb = New-Object System.Text.StringBuilder 1024
    [void][InstallerUi.Win]::GetWindowTextW($Handle, $sb, 1024)
    return $sb.ToString()
}

function Get-WindowClass {
    param([IntPtr]$Handle)
    $sb = New-Object System.Text.StringBuilder 256
    [void][InstallerUi.Win]::GetClassNameW($Handle, $sb, 256)
    return $sb.ToString()
}

function Get-WindowRect {
    param([IntPtr]$Handle)
    $r = New-Object InstallerUi.Win+RECT
    [void][InstallerUi.Win]::GetWindowRect($Handle, [ref]$r)
    return $r
}

function Get-ClientRect {
    param([IntPtr]$Handle)
    $r = New-Object InstallerUi.Win+RECT
    [void][InstallerUi.Win]::GetClientRect($Handle, [ref]$r)
    return $r
}

function Get-ClientOrigin {
    <# Esquina superior izquierda del area cliente en coordenadas de pantalla. #>
    param([IntPtr]$Handle)
    $p = New-Object InstallerUi.Win+POINT
    [void][InstallerUi.Win]::ClientToScreen($Handle, [ref]$p)
    return $p
}

function Get-AllWindows {
    <# Todas las ventanas de nivel superior, incluidas las ocultas. #>
    $result = New-Object System.Collections.ArrayList
    $callback = [InstallerUi.Win+EnumWindowsProc]{
        param($h, $l)
        [void]$result.Add($h)
        return $true
    }
    [void][InstallerUi.Win]::EnumWindows($callback, [IntPtr]::Zero)
    return $result
}

function Get-TopLevelWindows {
    $result = New-Object System.Collections.ArrayList
    $callback = [InstallerUi.Win+EnumWindowsProc]{
        param($h, $l)
        if ([InstallerUi.Win]::IsWindowVisible($h)) {
            $t = Get-WindowText $h
            if ($t) { [void]$result.Add($h) }
        }
        return $true
    }
    [void][InstallerUi.Win]::EnumWindows($callback, [IntPtr]::Zero)
    return $result
}

function Send-KeyTo {
    <# Envia una tecla a una ventana concreta: recupera el primer plano y
       comprueba que la ventana destino lo tiene antes de pulsar. En este
       equipo hay otras sesiones de agente que roban el foco. #>
    param(
        [Parameter(Mandatory)][IntPtr]$Window,
        [Parameter(Mandatory)][string]$Keys,
        [int]$TimeoutSeconds = 30
    )
    if (-not (Focus-Installer -Handle $Window -TimeoutSeconds $TimeoutSeconds)) {
        throw ("No se pudo poner en primer plano la ventana '" + (Get-WindowText $Window) + "'.")
    }
    $fg = Get-ForegroundWindow
    if (-not (Test-IsForeground -Handle $Window)) {
        throw ("El primer plano se ha ido a '" + (Get-WindowText $fg) + "'; la tecla no se envia.")
    }
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Start-Sleep -Milliseconds 350
}

function Get-WindowPid {
    param([IntPtr]$Handle)
    $pidOut = [uint32]0
    [void][InstallerUi.Win]::GetWindowPid($Handle, [ref]$pidOut)
    return $pidOut
}

function Test-Handle {
    param([IntPtr]$Handle)
    return ($Handle.ToInt64() -eq 0)
}

function Find-Window {
    param(
        [Parameter(Mandatory)][string]$TitleLike,
        [int]$TimeoutSeconds = 30,
        [switch]$VisibleOnly
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        foreach ($h in Get-TopLevelWindows) {
            $t = Get-WindowText $h
            if ($t -like $TitleLike) {
                if ($VisibleOnly -and -not [InstallerUi.Win]::IsWindowVisible($h)) { continue }
                return $h
            }
        }
        Start-Sleep -Milliseconds 250
    }
    return [IntPtr]::Zero
}

function Set-Foreground {
    <# Trae la ventana al frente de verdad: AttachThreadInput es necesario
       cuando el proceso actual no es el de primer plano (hay otras sesiones
       de agente activas en este equipo). #>
    param([IntPtr]$Handle)
    $target = [InstallerUi.Win]::GetWindowThreadProcessId($Handle, [IntPtr]::Zero)
    $self = [InstallerUi.Win]::GetCurrentThreadId()
    $attached = $false
    try {
        if ($target -ne 0) { $attached = [InstallerUi.Win]::AttachThreadInput($self, $target, $true) }
        [void][InstallerUi.Win]::ShowWindow($Handle, 9)          # SW_RESTORE
        [void][InstallerUi.Win]::BringWindowToTop($Handle)
        [void][InstallerUi.Win]::SetForegroundWindow($Handle)
        [void][InstallerUi.Win]::SetFocus($Handle)
    }
    finally {
        if ($attached) { [void][InstallerUi.Win]::AttachThreadInput($self, $target, $false) }
    }
    Start-Sleep -Milliseconds 300
}

function Get-ForegroundWindow { return [InstallerUi.Win]::GetForegroundWindow() }

function Test-IsForeground {
    param([IntPtr]$Handle)
    $fg = [InstallerUi.Win]::GetForegroundWindow()
    if (Test-Handle $fg) { return $false }
    # La ventana puede no ser la de primer plano si el foco esta en un control
    # hijo: se compara el hilo.
    $a = [InstallerUi.Win]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
    $b = [InstallerUi.Win]::GetWindowThreadProcessId($Handle, [IntPtr]::Zero)
    return ($a -ne 0 -and $a -eq $b)
}

function Save-WindowScreenshot {
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [Parameter(Mandatory)][string]$Path
    )
    $r = Get-WindowRect $Handle
    $w = $r.Right - $r.Left
    $h = $r.Bottom - $r.Top
    if ($w -le 0 -or $h -le 0) { throw 'Ventana sin rectangulo valido.' }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    try {
        $ok = [InstallerUi.Win]::PrintWindow($Handle, $hdc, 2)
        if (-not $ok) { $ok = [InstallerUi.Win]::PrintWindow($Handle, $hdc, 0) }
    }
    finally {
        $g.ReleaseHdc($hdc)
        $g.Dispose()
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $Path
}

function Get-FocusedControl {
    param([IntPtr]$Handle)
    # Se usa el hilo de la ventana objetivo, no el hilo en primer plano: en
    # este equipo puede haber otras ventanas activas de otras sesiones.
    $thread = [InstallerUi.Win]::GetWindowThreadProcessId($Handle, [IntPtr]::Zero)
    if ($thread -eq 0) { return $null }
    $gti = New-Object InstallerUi.Win+GUITHREADINFO
    $gti.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($gti)
    if (-not [InstallerUi.Win]::GetGUIThreadInfo($thread, [ref]$gti)) { return $null }
    if ($gti.hwndFocus.ToInt64() -eq 0) { return $null }
    $rect = Get-WindowRect $gti.hwndFocus
    $origin = Get-ClientOrigin -Handle $Handle
    return [pscustomobject]@{
        Handle = $gti.hwndFocus
        Class = Get-WindowClass $gti.hwndFocus
        Text = Get-WindowText $gti.hwndFocus
        Left = $rect.Left - $origin.X
        Top = $rect.Top - $origin.Y
        Right = $rect.Right - $origin.X
        Bottom = $rect.Bottom - $origin.Y
    }
}

function Send-Key {
    param(
        [Parameter(Mandatory)][string]$Keys,
        [int]$DelayMs = 350
    )
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Start-Sleep -Milliseconds $DelayMs
}

function Send-Text {
    param(
        [Parameter(Mandatory)][string]$Text,
        [int]$DelayMs = 200
    )
    [System.Windows.Forms.SendKeys]::SendWait($Text)
    Start-Sleep -Milliseconds $DelayMs
}

function Get-ControlText {
    param([IntPtr]$Handle)
    $sb = New-Object System.Text.StringBuilder 1024
    [void][InstallerUi.Win]::SendMessageW($Handle, 0x000D, [IntPtr]1024, $sb)  # WM_GETTEXT
    return $sb.ToString()
}

function Get-ChildWindows {
    param([IntPtr]$Parent)
    $result = New-Object System.Collections.ArrayList
    $callback = [InstallerUi.Win+EnumWindowsProc]{
        param($h, $l)
        [void]$result.Add($h)
        return $true
    }
    [void][InstallerUi.Win]::EnumChildWindows($Parent, $callback, [IntPtr]::Zero)
    return $result
}

function Get-ChildControls {
    <# Controles hijos con coordenadas relativas al area cliente de la ventana. #>
    param([IntPtr]$Parent)
    $origin = Get-ClientOrigin -Handle $Parent
    Get-ChildWindows -Parent $Parent | ForEach-Object {
        $r = Get-WindowRect $_
        [pscustomobject]@{
            Handle = $_
            Class = Get-WindowClass $_
            Text = Get-WindowText $_
            Left = $r.Left - $origin.X
            Top = $r.Top - $origin.Y
            Right = $r.Right - $origin.X
            Bottom = $r.Bottom - $origin.Y
        }
    }
}

function Get-WindowAtPoint {
    <# Que ventana hay en un punto de pantalla (para saber quien recibe el clic). #>
    param([Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y)
    $p = New-Object InstallerUi.Win+POINT
    $p.X = $X
    $p.Y = $Y
    return [InstallerUi.Win]::WindowFromPoint($p)
}

function Focus-Installer {
    <# Intenta quedarse con el primer plano y el foco. En este equipo hay
       dialogos del sistema y otras ventanas de otros agentes que lo roban:
       se reintenta hasta que la ventana del instalador responde. #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [int]$TimeoutSeconds = 60
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Set-TopMost -Handle $Handle -On $true
        Click-TitleBar -Handle $Handle
        if (Test-IsForeground -Handle $Handle) { return $true }
        $fg = Get-ForegroundWindow
        $fgText = if (Test-Handle $fg) { '(sin ventana)' } else { Get-WindowText $fg }
        Start-Sleep -Milliseconds 700
    }
    return $false
}

function Set-TopMost {
    <# En este equipo hay varias ventanas de otros agentes en primer plano:
       el EXE de la prueba tiene que quedar por encima de todas para poder
       recibir el raton y el teclado. #>
    param([Parameter(Mandatory)][IntPtr]$Handle, [bool]$On = $true)
    $flags = 0x0001 -bor 0x0002 -bor 0x0040   # NOSIZE | NOMOVE | SHOWWINDOW
    if ($On) { [void][InstallerUi.Win]::SetWindowPos($Handle, [IntPtr](-1), 0, 0, 0, 0, $flags) }
    else { [void][InstallerUi.Win]::SetWindowPos($Handle, [IntPtr](-2), 0, 0, 0, 0, $flags) }
    Start-Sleep -Milliseconds 200
}

function Click-Screen {
    <# Clic real con el raton: es la unica forma fiable de dar el foco cuando
       hay otras ventanas de primer plano en el escritorio. #>
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [int]$DelayMs = 350
    )
    [void][InstallerUi.Win]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 120
    [InstallerUi.Win]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)   # LEFTDOWN
    [InstallerUi.Win]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)   # LEFTUP
    Start-Sleep -Milliseconds $DelayMs
}

function Click-Client {
    <# Clic en coordenadas relativas al area cliente de la ventana. #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y
    )
    $origin = Get-ClientOrigin -Handle $Handle
    Click-Screen -X ($origin.X + $X) -Y ($origin.Y + $Y)
}

function Click-TitleBar {
    <# Clic en la barra de titulo: trae la ventana al frente y le da el foco. #>
    param([Parameter(Mandatory)][IntPtr]$Handle)
    $r = Get-WindowRect $Handle
    Click-Screen -X ($r.Left + 120) -Y ($r.Top + 10)
}

function Set-Text {
    <# Escribe texto en un control (WM_SETTEXT). #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [Parameter(Mandatory)][string]$Text
    )
    [void][InstallerUi.Win]::SendMessageW($Handle, 0x000C, [IntPtr]::Zero, $Text)
    Start-Sleep -Milliseconds 150
}

function Type-Char {
    <# Envia un caracter como si el usuario lo escribiera (WM_CHAR). #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [Parameter(Mandatory)][char]$Char
    )
    [void][InstallerUi.Win]::SendMessageW($Handle, 0x0102, [IntPtr][int][char]$Char, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 25
}

function Click-Control {
    <# Clic programatico en un control propio (boton). Se usa cuando otra
       ventana del sistema tiene el primer plano y no se puede usar el raton. #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [int]$X = 8,
        [int]$Y = 8
    )
    $lParam = [IntPtr](($Y -shl 16) -bor ($X -band 0xFFFF))
    [void][InstallerUi.Win]::SendMessageW($Handle, 0x0201, [IntPtr]1, $lParam)   # WM_LBUTTONDOWN
    Start-Sleep -Milliseconds 60
    [void][InstallerUi.Win]::SendMessageW($Handle, 0x0202, [IntPtr]0, $lParam)   # WM_LBUTTONUP
    Start-Sleep -Milliseconds 250
}

function Post-Key {
    <# Envia una tecla a la ventana o al control indicado (WM_KEYDOWN/WM_KEYUP).
       Permite ejercitar el manejador de teclado de Inno cuando otra ventana
       del sistema impide usar el teclado fisico. #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [Parameter(Mandatory)][int]$VirtualKey,
        [int]$DelayMs = 300
    )
    [void][InstallerUi.Win]::PostMessageW($Handle, 0x0100, [IntPtr]$VirtualKey, [IntPtr]::Zero)  # WM_KEYDOWN
    Start-Sleep -Milliseconds 60
    [void][InstallerUi.Win]::PostMessageW($Handle, 0x0101, [IntPtr]$VirtualKey, [IntPtr]::Zero)  # WM_KEYUP
    Start-Sleep -Milliseconds $DelayMs
}

function Click-Button {
    <# Pulsa un boton por su texto dentro de una ventana. #>
    param(
        [Parameter(Mandatory)][IntPtr]$Parent,
        [Parameter(Mandatory)][string]$TextLike
    )
    foreach ($ctl in Get-ChildControls -Parent $Parent) {
        if ($ctl.Text -like $TextLike -and $ctl.Class -match 'Button|TNew') {
            [void][InstallerUi.Win]::SendMessageW($ctl.Handle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)  # BM_CLICK
            return $true
        }
    }
    return $false
}

function Stop-InstallerProcesses {
    <# Inno Setup lanza un proceso hijo "<nombre>.tmp": hay que cerrar los dos. #>
    param([Parameter(Mandatory)][string]$NamePattern)
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like $NamePattern } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}
