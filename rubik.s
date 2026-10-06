# rubik.s: optimal 2x2x2 solver in RV32I (no M extension)

        .data
input:   .string "21345671111111"     # 要解的方塊（14 碼）
cube_p:  .zero   7                    # 座位：每格 0～6
cube_o:  .zero   7                    # 坐姿：每格 0～2
lehmer:  .zero   6                    # 每個位置「後面有幾個比我小」
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

        # ===== 4.3：座位號碼 p，步驟 a：數「後面有幾個比我小」=====
        la    t0, cube_p
        la    t3, lehmer
        li    t4, 6
        la    a1, cube_p
        addi  a1, a1, 7           # a1 = cube_p 結尾
lehmer_i:
        lbu   t1, 0(t0)           # t1 = 我的號碼
        li    t5, 0               # 計數
        addi  t6, t0, 1           # 從我後面那個人開始看
lehmer_j:
        lbu   t2, 0(t6)           # t2 = 後面那個人的號碼
        sltu  a2, t2, t1          # 他比我小嗎？
        add   t5, t5, a2          # 計數 + 1 或 + 0
        addi  t6, t6, 1
        bltu  t6, a1, lehmer_j
        sb    t5, 0(t3)           # 存進 lehmer[i]
        addi  t0, t0, 1
        addi  t3, t3, 1
        addi  t4, t4, -1
        bnez  t4, lehmer_i

        # ===== 步驟 b：p = Horner，乘法拆成 shift + add =====
        la    t0, lehmer
        lbu   s2, 0(t0)           # s2 = p = c0

        slli  t1, s2, 2           # p = p × 6 + c1
        slli  t2, s2, 1
        add   s2, t1, t2
        lbu   t3, 1(t0)
        add   s2, s2, t3

        slli  t1, s2, 2           # p = p × 5 + c2
        add   s2, t1, s2
        lbu   t3, 2(t0)
        add   s2, s2, t3

        slli  s2, s2, 2           # p = p × 4 + c3
        lbu   t3, 3(t0)
        add   s2, s2, t3

        slli  t1, s2, 1           # p = p × 3 + c4
        add   s2, t1, s2
        lbu   t3, 4(t0)
        add   s2, s2, t3

        slli  s2, s2, 1           # p = p × 2 + c5
        lbu   t3, 5(t0)
        add   s2, s2, t3

        # 暫時：印出 p 檢查，然後結束
        mv    a0, s2
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
