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

# Host memory per guest byte

## Method
- Program: measure/fill.s (sw into SIZE bytes from 0x20000000, then spin 5×10⁷ iterations)
- Tool: measure/peakmem.ps1 (samples PeakWorkingSet64 of the Ripes process every 100 ms)
- Processor: RV32_ISS

## Raw data
| SIZE (bytes) | instructions retired | run 1 (B) | run 2 (B) | mean (B) |
|---|---|---|---|---|
| 4,096 | 100,003,080 | 25,018,368 | 25,018,368 | 25,018,368 |
| 1,048,576 | 100,786,440 | 110,166,016 | 108,896,256 | 109,531,136 |
| 4,194,304 | 103,145,736 | 363,225,088 | 361,820,160 | 362,522,624 |

## Result
| pair | host bytes / guest byte |
|---|---|
| 1 MiB − 4 KiB | 80.9 |
| 4 MiB − 4 KiB | 80.6 |
| 4 MiB − 1 MiB | 80.4 |