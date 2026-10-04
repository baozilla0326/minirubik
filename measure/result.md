# Ripes simulation-rate measurement

## Environment
- OS: Windows 11 Home (10.0.26200)
- CPU: （填你的 CPU 型號）
- RAM: （填記憶體大小）
- Ripes: v2.2.6-106-g5b8a616 (continuous build, 2026-08-18)

## Method
- Program: measure/loop.s (countdown loop, 2 instructions per iteration)
- Command: （貼你用的 PowerShell 指令）
- Two runs per processor (small N and large N), 3 repetitions each;
  rate = Δinstructions / Δseconds to cancel Ripes startup time.

## Raw data
### RV32_ISS
| N | instructions retired | run 1 (s) | run 2 (s) | run 3 (s) | mean (s) |
|---|---|---|---|---|---|
| 1,000 | 2,003 | ... | ... | ... | ... |
| 50,000,000 | 100,000,004 | ... | ... | ... | ... |

### RV32_5S
（同上）

## Result
| Processor | instructions / second |
|---|---|
| RV32_ISS | ... |
| RV32_5S | ... |