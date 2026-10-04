# peakmem.ps1: run a Ripes program in CLI mode and report the peak working set
# of the Ripes process, sampled every 100 ms while it runs.
#
# Usage (PowerShell):
#   .\peakmem.ps1 -Ripes <path to Ripes.exe> -Src <path to .s file> [-Proc RV32_ISS]

param(
    [Parameter(Mandatory = $true)] [string] $Ripes,
    [Parameter(Mandatory = $true)] [string] $Src,
    [string] $Proc = 'RV32_ISS'
)

$out = Join-Path $env:TEMP 'iret.txt'
$p = Start-Process -FilePath $Ripes -PassThru -WindowStyle Hidden -ArgumentList @(
    '--mode', 'cli', '--src', $Src, '-t', 'asm', '--proc', $Proc, '--iret', '--output', $out)

$peak = 0
while (-not $p.HasExited) {
    $p.Refresh()
    try { if ($p.PeakWorkingSet64 -gt $peak) { $peak = $p.PeakWorkingSet64 } } catch {}
    Start-Sleep -Milliseconds 100
}

"Peak: {0:N0} bytes" -f $peak
Get-Content $out
