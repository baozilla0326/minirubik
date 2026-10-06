# all11_run.ps1: run every ELF in a folder on Ripes and record retired
# instructions as CSV (state, instructions).
#
# Usage (PowerShell):
#   .\all11_run.ps1 -Ripes <path to Ripes.exe> [-Dir all11] [-Out all11_ref.csv]

param(
    [Parameter(Mandatory = $true)] [string] $Ripes,
    [string] $Dir = 'all11',
    [string] $Out = 'all11_ref.csv',
    [string] $Type = 'elf'
)

$files = Get-ChildItem (Join-Path $PSScriptRoot $Dir) -Filter "*.$Type" | Sort-Object Name
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('state,instructions')
$i = 0
foreach ($f in $files) {
    $i++
    $text = & $Ripes --mode cli --src $f.FullName -t $Type --proc RV32_ISS --iret | Out-String
    $n = if ($text -match 'retired\s+(\d+)') { $Matches[1] } else { 'ERROR' }
    $rows.Add("$($f.BaseName),$n")
    if ($i % 100 -eq 0) { Write-Host "$i / $($files.Count)" }
}
$rows | Set-Content -Encoding ascii (Join-Path $PSScriptRoot $Out)
$nums = $rows | Select-Object -Skip 1 | ForEach-Object { ($_ -split ',')[1] } | Where-Object { $_ -ne 'ERROR' } | ForEach-Object { [long]$_ }
$max = ($nums | Measure-Object -Maximum).Maximum
$worst = ($rows | Where-Object { $_ -match ",$max$" } | Select-Object -First 1)
"runs: $($files.Count), errors: $($files.Count - $nums.Count)"
"max instructions: $max  ($worst)"
"mean instructions: {0:N0}" -f ($nums | Measure-Object -Average).Average
