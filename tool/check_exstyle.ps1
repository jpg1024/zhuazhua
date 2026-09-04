$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public static List<IntPtr> found = new List<IntPtr>();
  public static uint target;
  public static bool CB(IntPtr h, IntPtr lp) {
    uint pid; GetWindowThreadProcessId(h, out pid);
    if (pid == target && IsWindowVisible(h)) found.Add(h);
    return true;
  }
}
"@
$p = @(Get-Process zoo_desktop_pet -ErrorAction SilentlyContinue)[0]
if (-not $p) { Write-Output 'APP NOT RUNNING'; exit 1 }
$all = @(Get-Process zoo_desktop_pet -ErrorAction SilentlyContinue)
Write-Output ("instance count: " + $all.Count)
[W]::target = [uint32]$p.Id
[W]::found.Clear()
$del = [W+EnumProc]::CreateDelegate([W+EnumProc], [W], 'CB')
[W]::EnumWindows($del, [IntPtr]::Zero) | Out-Null
Write-Output ("visible windows of pid " + $p.Id + ": " + [W]::found.Count)
foreach ($h in [W]::found) {
  $style = [W]::GetWindowLongPtr($h, -20).ToInt64()
  $layered = ($style -band 0x80000) -ne 0
  $transparent = ($style -band 0x20) -ne 0
  Write-Output ("hwnd=" + $h + " exstyle=0x" + $style.ToString('X') + " LAYERED=" + $layered + " TRANSPARENT=" + $transparent)
}
