# loop.s：測 Ripes 每秒執行幾條指令

        .equ  N, 1000       # 要跑幾圈

        .text
main:
        li    t0, N             # 計數器從 N 開始

loop:
        addi  t0, t0, -1        # 計數器減 1
        bnez  t0, loop          # 不是 0 就回到 loop

        li    a7, 10            # 服務編號 10：結束程式
        ecall