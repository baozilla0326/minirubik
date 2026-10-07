# run_tests.ps1: build rubik.s once per test case and run it on Ripes.
# Each case replaces the input string and EXPECT, appends tables.s, and checks
# the program's own exit code (0 = path solves the cube and has the expected
# length). Also reports retired instructions.
#
# Usage (PowerShell, from measure/):
#   powershell -ExecutionPolicy Bypass -File .\run_tests.ps1 -Ripes $ripes [-Proc RV32_ISS]

param(
    [Parameter(Mandatory = $true)] [string] $Ripes,
    [string] $Proc = 'RV32_ISS'
)

$root = Split-Path -Parent $PSScriptRoot
$src = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'rubik.s')
$tables = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'tables.s')

$cases = @(
    @{ Name = 'solved';             State = '12345671111111'; Expect = 0 },
    @{ Name = 'short (R then B)';   State = '25346712313322'; Expect = 2 },
    @{ Name = 'distance 11 (T6)';   State = '21345671111111'; Expect = 11 },
    @{ Name = 'worst for search';   State = '54721631111111'; Expect = 11 }
)

$fails = 0
foreach ($c in $cases) {
    $asm = $src -replace 'input:   \.string "\d{14}"', ('input:   .string "' + $c.State + '"')
    $asm = $asm -replace '\.equ  EXPECT, \d+', ('.equ  EXPECT, ' + $c.Expect)
    $file = Join-Path $env:TEMP ('rubik_test_' + $c.State + '.s')
    [IO.File]::WriteAllText($file, $asm + "`n" + $tables)

    $out = & $Ripes --mode cli --src $file -t asm --proc $Proc --iret 2>&1 | Out-String
    $code = if ($out -match 'exited with code: (\d+)') { [int]$Matches[1] } else { -1 }
    $iret = if ($out -match 'instructions retired\s+(\d+)') { $Matches[1] } else { '?' }
    $path = ($out -split "`n")[0].Trim() -replace '\s+', ' '
    $status = if ($code -eq 0) { 'PASS' } else { 'FAIL'; $fails++ }
    '{0,-4} {1,-18} {2} expect {3,2}  iret {4,10}  [{5}]' -f $status, $c.Name, $c.State, $c.Expect, $iret, $path
}
if ($fails) { "$fails case(s) failed"; exit 1 } else { 'all cases passed' }
