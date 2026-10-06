# gs-install.ps1 - installiert Ghostscript aus dem offiziellen Installer, indem die
# Schaltflächen des Installationsfensters automatisch gedrückt werden.
#
# Hintergrund: Der Ghostscript-Installer (NSIS) ignoriert /S - er zeigt trotzdem
# sein Fenster und wartet endlos (Chocolatey löst das mit AutoHotkey).  Dieses
# Skript startet den Installer und drückt "Next", "I Agree", "Install", "Close" ...
# (BM_CLICK) bis der Installer beendet ist.  Es muss im SELBEN Rechte-Niveau wie
# der Installer laufen (Windows blockiert Fensternachrichten an höhere Rechte);
# install.ps1 startet deshalb dieses Skript selbst mit Administrator-Rechten.
#
# Aufruf: gs-install.ps1 -Installer <gs...w64.exe> [-TimeoutSec 600]
# Exit-Code: 0 = Installer sauber beendet, 1 = Zeitüberschreitung/Fehler.
# Datei als UTF-8 MIT BOM speichern (Windows PowerShell 5.1).
param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [int]$TimeoutSec = 600
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Text;
using System.Runtime.InteropServices;
public static class GsWin {
    delegate bool CB(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(CB cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, CB cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    const uint BM_CLICK = 0x00F5;
    static string Text(IntPtr h) { var t = new StringBuilder(256); GetWindowText(h, t, 256); return t.ToString(); }
    static string Cls(IntPtr h) { var t = new StringBuilder(256); GetClassName(h, t, 256); return t.ToString(); }
    // Drückt die erste sichtbare, aktive Schaltfläche des Prozesses, deren Text in 'wanted' vorkommt
    // (Reihenfolge = Vorrang).  Rückgabe: Text der gedrückten Schaltfläche oder "".
    public static string ClickButton(uint pid, string[] wanted, out string seen) {
        var buttons = new List<KeyValuePair<IntPtr, string>>();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid) {
                EnumChildWindows(h, (c, l2) => {
                    if (Cls(c) == "Button" && IsWindowVisible(c) && IsWindowEnabled(c))
                        buttons.Add(new KeyValuePair<IntPtr, string>(c, Text(c)));
                    return true;
                }, IntPtr.Zero);
            }
            return true;
        }, IntPtr.Zero);
        var sb = new StringBuilder();
        foreach (var b in buttons) sb.Append("[" + b.Value + "]");
        seen = sb.ToString();
        foreach (var w in wanted)
            foreach (var b in buttons)
                if (b.Value.Replace("&", "").Trim().Equals(w, StringComparison.OrdinalIgnoreCase)) {
                    SendMessage(b.Key, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
                    return b.Value;
                }
        return "";
    }
}
"@

$p = Start-Process -FilePath $Installer -PassThru
$wanted = @("Install", "Next >", "Next", "I Agree", "Finish", "Close", "OK")
$last = ""
$lastClick = [DateTime]::MinValue
$sw = [Diagnostics.Stopwatch]::StartNew()
while (-not $p.HasExited) {
    if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) {
        try { $p.Kill() } catch { }
        Write-Host "Zeitüberschreitung beim Installer (zuletzt sichtbare Schaltflächen: $last)"
        exit 1
    }
    Start-Sleep -Milliseconds 700
    if (([DateTime]::Now - $lastClick).TotalSeconds -lt 1.5) { continue }
    $seen = ""
    $clicked = [GsWin]::ClickButton([uint32]$p.Id, $wanted, [ref]$seen)
    if ($seen -ne "" -and $seen -ne $last) { Write-Host "Installer-Fenster: $seen"; $last = $seen }
    if ($clicked -ne "") { Write-Host "  -> '$($clicked.Replace('&',''))' gedrückt"; $lastClick = [DateTime]::Now }
}
Write-Host "Installer beendet (Exit-Code $($p.ExitCode))."
exit $p.ExitCode
