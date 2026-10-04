# fill.s：寫滿一塊記憶體，量 Ripes 用了多少電腦記憶體

        .equ  BASE, 0x20000000      # 從這個位址開始寫
        .equ  SIZE, 4194304         # 要寫幾 bytes（1 MiB）
        .equ  SPIN, 50000000        # 寫完後空轉，讓我們有時間量

        .text
main:
        li    t0, BASE              # t0 = 目前要寫的位址
        li    t1, SIZE
        add   t1, t0, t1            # t1 = 結束位址
        li    t2, 1                 # 要寫的值

fill:
        sw    t2, 0(t0)             # 寫一個 word
        addi  t0, t0, 4             # 往後移 4 bytes
        bltu  t0, t1, fill          # 還沒到結束位址就繼續

        li    t3, SPIN              # 寫完了，空轉約 6 秒
spin:
        addi  t3, t3, -1
        bnez  t3, spin

        li    a7, 10
        ecall