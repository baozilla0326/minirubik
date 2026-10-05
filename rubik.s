# rubik.s: optimal 2x2x2 solver in RV32I (no M extension)

        .data
input:   .string "12345672111113"     # 要解的方塊（14 碼）
cube_p:  .zero   7                    # 座位：每格 0～6
cube_o:  .zero   7                    # 坐姿：每格 0～2
msg_bad: .string "invalid state\n"
msg_ok:  .string "valid\n"

        .text
main:
        # ===== 4.2：讀入並檢查 =====
        # 前 7 碼：座位，0～6 且不重複
        la    t0, input
        la    t3, cube_p
        li    t4, 7
        li    t5, 0                   # 點名表
loop1:
        lbu   t1, 0(t0)
        addi  t1, t1, -49
        li    t2, 7
        bgeu  t1, t2, invalid
        li    t2, 1
        sll   t2, t2, t1
        and   t6, t5, t2
        bnez  t6, invalid
        or    t5, t5, t2
        sb    t1, 0(t3)
        addi  t0, t0, 1
        addi  t3, t3, 1
        addi  t4, t4, -1
        bnez  t4, loop1

        # 後 7 碼：坐姿，0～2，加總
        la    t3, cube_o
        li    t4, 7
        li    t5, 0                   # 坐姿總和
loop2:
        lbu   t1, 0(t0)
        addi  t1, t1, -49
        li    t2, 3
        bgeu  t1, t2, invalid
        add   t5, t5, t1
        sb    t1, 0(t3)
        addi  t0, t0, 1
        addi  t3, t3, 1
        addi  t4, t4, -1
        bnez  t4, loop2

        # 第 15 個字必須是字串結尾
        lbu   t1, 0(t0)
        bnez  t1, invalid

        # 坐姿總和 mod 3 必須是 0
        li    t2, 3
mod3:
        bltu  t5, t2, mod3_done
        addi  t5, t5, -3
        j     mod3
mod3_done:
        bnez  t5, invalid

        # ===== 4.3：坐姿號碼 o =====
        la    t0, cube_o
        li    t4, 6
        li    s1, 0               # s1 = o
ori_loop:
        lbu   t1, 0(t0)
        slli  t2, s1, 1           # t2 = o × 2
        add   s1, s1, t2          # s1 = o × 3
        add   s1, s1, t1          # s1 = o × 3 + cube_o[i]
        addi  t0, t0, 1
        addi  t4, t4, -1
        bnez  t4, ori_loop

        # 暫時：印出 o 檢查，然後結束
        mv    a0, s1
        li    a7, 1
        ecall
        li    a7, 10
        ecall

invalid:
        la    a0, msg_bad
        li    a7, 4
        ecall
        li    a7, 10
        ecall
