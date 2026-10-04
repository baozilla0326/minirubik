# Ripes simulation-rate measurement

## Environment
- OS: Windows 11 Home (10.0.26200)
- CPU: 11th Gen Intel Core i9-11900H @ 2.50GHz
- RAM: 16 GB
- Ripes: v2.2.6-106-g5b8a616 (continuous build, 2026-08-18)

## Method
- Program: measure/loop.s (countdown loop, 2 instructions per iteration)
- Command (PowerShell):
  `Measure-Command { & $ripes --mode cli --src $src -t asm --proc <PROC> --iret --output $env:TEMP\iret.txt | Out-Null }`
- Two runs per processor (small N and large N), 3 repetitions each;
  rate = Δinstructions / Δseconds to cancel Ripes startup time.
- The very first run (cold start) was discarded.

## Raw data
### RV32_ISS
| N | instructions retired | run 1 (s) | run 2 (s) | run 3 (s) | mean (s) |
|---|---|---|---|---|---|
| 1,000 | 2,003 | 0.0619 | 0.0519 | 0.0532 | 0.0557 |
| 50,000,000 | 100,000,004 | 5.8546 | 5.9432 | 5.8297 | 5.8758 |

Δ = 99,998,001 instructions / 5.8201 s

### RV32_5S
| N | instructions retired | run 1 (s) | run 2 (s) | run 3 (s) | mean (s) |
|---|---|---|---|---|---|
| 1,000 | 2,003 | 0.0749 | 0.0663 | 0.0645 | 0.0686 |
| 2,000,000 | 4,000,004 | 26.5492 | 26.3292 | 26.5535 | 26.4773 |

Δ = 3,998,001 instructions / 26.4087 s

## Result
| Processor | instructions / second | assignment reference |
|---|---|---|
| RV32_ISS | 1.72 × 10⁷ | 1.09 × 10⁶ |
| RV32_5S | 1.51 × 10⁵ | 2.05 × 10⁴ |