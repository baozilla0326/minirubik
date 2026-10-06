# rubik.s: optimal 2x2x2 solver in RV32I (no M extension)

        .data
input:   .string "21345671111111"     # 要解的方塊（14 碼）
cube_p:  .zero   7                    # 座位：每格 0～6
cube_o:  .zero   7                    # 坐姿：每格 0～2
lehmer:  .zero   6                    # 每個位置「後面有幾個比我小」
st_p:    .zero   24                   # 每一層的 p（halfword × 12）
st_o:    .zero   24                   # 每一層的 o
st_q:    .zero   24                   # 每一層的 q
face:    .zero   12                   # 每一層正在試的面
turn:    .zero   12                   # 每一層這一面轉了幾次（2 = 換下一面）
nextf:   .zero   12                   # 每一層下一個要試的面
path:    .zero   12                   # 解答
msg_sp:  .byte   32, 0                 # 一個空白字元
msg_nl:  .byte   10, 0                 # 換行字元
mnames:                               # 9 個轉法名字，每個 4 bytes（ASCII 碼）
         .byte 82, 0, 0, 0,  82, 50, 0, 0,  82, 39, 0, 0
         .byte 66, 0, 0, 0,  66, 50, 0, 0,  66, 39, 0, 0
         .byte 68, 0, 0, 0,  68, 50, 0, 0,  68, 39, 0, 0
        .align 2
row_perm: .word 0, 10080, 20160        # 每一面那一列在 perm_move 裡的位移（bytes）
row_ori:  .word 0, 1458, 2916
row_pair: .word 0, 882, 1764
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

        # ===== 4.3：1、2 號角塊的號碼 q =====
        la    t0, cube_p
        la    t3, cube_o
        li    t4, 0               # t4 = 位置 i
        li    t5, 7
q_loop:
        lbu   t1, 0(t0)           # t1 = 這個位置坐的是幾號
        lbu   t2, 0(t3)           # t2 = 這個位置的坐姿
        slli  a2, t4, 1
        add   a2, a2, t4          # a2 = i × 3
        add   a2, a2, t2          # a2 = i × 3 + 坐姿
        bnez  t1, q_not0          # 不是 0 號 → 跳過
        mv    a3, a2              # a3 = c0
q_not0:
        li    t6, 1
        bne   t1, t6, q_next      # 不是 1 號 → 跳過
        mv    a4, a2              # a4 = c1
q_next:
        addi  t0, t0, 1
        addi  t3, t3, 1
        addi  t4, t4, 1
        bltu  t4, t5, q_loop

        # q = c0 × 21 + c1
        slli  t1, a3, 4           # 16 × c0
        slli  t2, a3, 2           # 4 × c0
        add   s3, t1, t2
        add   s3, s3, a3          # 21 × c0
        add   s3, s3, a4          # + c1

        # ===== 4.4：IDA* 搜尋 =====
        # 每一層的狀態：st_p/st_o/st_q[d] 是第 d 層的方塊，
        # face/turn/nextf[d] 是第 d 層正在試的面、轉了幾次、下一個要試的面。
        la    t0, st_p
        sh    s2, 0(t0)           # st_p[0] = p
        la    t0, st_o
        sh    s1, 0(t0)           # st_o[0] = o
        la    t0, st_q
        sh    s3, 0(t0)           # st_q[0] = q
        mv    a0, s2
        mv    a1, s1
        mv    a2, s3
        jal   ra, heur
        mv    s4, a0              # s4 = bound = h(起點)
        li    s6, 0               # s6 = 解答長度
        beqz  s4, found           # h = 0：已經解好

bound_loop:
        li    s5, 0               # s5 = d = 0
        la    t0, nextf
        sb    zero, 0(t0)         # nextf[0] = 0
        la    t0, turn
        li    t1, 2
        sb    t1, 0(t0)           # turn[0] = 2（要開始新的一面）

node_loop:
        bltz  s5, next_bound      # d < 0：這一輪全部試完
        la    t0, turn
        add   t0, t0, s5
        lbu   t1, 0(t0)           # t1 = turn[d]
        li    t2, 2
        bne   t1, t2, same_face   # 還沒轉滿 → 同一面再轉 90°

        # --- 開始新的一面 ---
        la    t0, nextf
        add   t0, t0, s5
        lbu   t3, 0(t0)           # t3 = f = nextf[d]
        beqz  s5, face_ok         # d = 0：沒有上一步
        la    t4, face
        add   t4, t4, s5
        lbu   t4, -1(t4)          # t4 = face[d-1]
        bne   t3, t4, face_ok
        addi  t3, t3, 1           # 同一面不連轉：跳過
face_ok:
        li    t2, 3
        bne   t3, t2, face_go
        addi  s5, s5, -1          # 三面都試完：退回上一層
        j     node_loop
face_go:
        la    t4, face
        add   t4, t4, s5
        sb    t3, 0(t4)           # face[d] = f
        addi  t4, t3, 1
        sb    t4, 0(t0)           # nextf[d] = f + 1
        la    t0, turn
        add   t0, t0, s5
        sb    zero, 0(t0)         # turn[d] = 0
        slli  t5, s5, 1           # 第 d 層的 halfword 位移
        la    t0, st_p
        add   t0, t0, t5
        lhu   t1, 0(t0)
        sh    t1, 2(t0)           # st_p[d+1] = st_p[d]
        la    t0, st_o
        add   t0, t0, t5
        lhu   t1, 0(t0)
        sh    t1, 2(t0)           # st_o[d+1] = st_o[d]
        la    t0, st_q
        add   t0, t0, t5
        lhu   t1, 0(t0)
        sh    t1, 2(t0)           # st_q[d+1] = st_q[d]
        j     apply_turn

same_face:
        addi  t1, t1, 1
        sb    t1, 0(t0)           # turn[d] += 1

apply_turn:
        # 第 d+1 層的方塊再轉 90°：三張轉移表各查一次
        la    t0, face
        add   t0, t0, s5
        lbu   t3, 0(t0)           # t3 = f
        slli  t3, t3, 2           # f × 4（rows 每格 4 bytes）
        slli  t5, s5, 1           # 第 d 層的 halfword 位移

        la    t0, row_perm
        add   t0, t0, t3
        lw    t0, 0(t0)           # 第 f 列的位移
        la    t6, perm_move
        add   t0, t0, t6          # t0 = perm_move 第 f 列的位址           # t0 = perm_move 第 f 列的位址
        la    t1, st_p
        add   t1, t1, t5
        lhu   t2, 2(t1)           # st_p[d+1]
        slli  t2, t2, 1
        add   t2, t0, t2
        lhu   a0, 0(t2)           # a0 = 新的 p
        sh    a0, 2(t1)

        la    t0, row_ori
        add   t0, t0, t3
        lw    t0, 0(t0)           # 第 f 列的位移
        la    t6, ori_move
        add   t0, t0, t6          # t0 = ori_move 第 f 列的位址
        la    t1, st_o
        add   t1, t1, t5
        lhu   t2, 2(t1)
        slli  t2, t2, 1
        add   t2, t0, t2
        lhu   a1, 0(t2)           # a1 = 新的 o
        sh    a1, 2(t1)

        la    t0, row_pair
        add   t0, t0, t3
        lw    t0, 0(t0)           # 第 f 列的位移
        la    t6, pair_move
        add   t0, t0, t6          # t0 = pair_move 第 f 列的位址
        la    t1, st_q
        add   t1, t1, t5
        lhu   t2, 2(t1)
        slli  t2, t2, 1
        add   t2, t0, t2
        lhu   a2, 0(t2)           # a2 = 新的 q
        sh    a2, 2(t1)

        jal   ra, heur            # a0 = h
        addi  t0, s5, 1
        add   t0, t0, a0          # d + 1 + h
        bltu  s4, t0, node_loop   # > bound：剪枝

        # path[d] = f × 3 + turn[d]
        la    t0, face
        add   t0, t0, s5
        lbu   t1, 0(t0)
        slli  t2, t1, 1
        add   t1, t1, t2          # f × 3
        la    t0, turn
        add   t0, t0, s5
        lbu   t2, 0(t0)
        add   t1, t1, t2
        la    t0, path
        add   t0, t0, s5
        sb    t1, 0(t0)

        addi  s5, s5, 1           # d + 1
        beqz  a0, solved          # h = 0：解好了
        la    t0, nextf
        add   t0, t0, s5
        sb    zero, 0(t0)         # nextf[d] = 0
        la    t0, turn
        add   t0, t0, s5
        li    t1, 2
        sb    t1, 0(t0)           # turn[d] = 2
        j     node_loop

next_bound:
        addi  s4, s4, 1
        j     bound_loop

solved:
        mv    s6, s5              # 解答長度 = d + 1

found:
        # ===== 4.5：印出答案 =====
        la    s7, path
        li    s8, 0
print_loop:
        bgeu  s8, s6, print_done
        add   t0, s7, s8
        lbu   t1, 0(t0)           # 轉法編號 0～8
        slli  t1, t1, 2
        la    a0, mnames
        add   a0, a0, t1          # 每個名字佔 4 bytes
        li    a7, 4
        ecall
        la    a0, msg_sp
        li    a7, 4
        ecall
        addi  s8, s8, 1
        j     print_loop
print_done:
        la    a0, msg_nl
        li    a7, 4
        ecall
        li    a7, 10
        ecall

# heur: a0 = p, a1 = o, a2 = q  →  a0 = h = max(D, G)
# Leaf function: calls nothing, uses only t registers, so no stack frame.
heur:
        # D 的格子：o × 49 + pair_pos[q]
        slli  t0, a1, 5           # 32o
        slli  t1, a1, 4           # 16o
        add   t0, t0, t1
        add   t0, t0, a1          # 49o
        la    t1, pair_pos
        add   t1, t1, a2
        lbu   t1, 0(t1)           # pair_pos[q]
        add   t0, t0, t1          # D 的格子
        la    t1, d_tab
        add   t1, t1, t0
        lbu   t2, 0(t1)           # t2 = D 表查到的值

        # G 的格子：p × 9 + pair_twist[q]
        slli  t0, a0, 3           # 8p
        add   t0, t0, a0          # 9p
        la    t1, pair_twist
        add   t1, t1, a2
        lbu   t1, 0(t1)           # pair_twist[q]
        add   t0, t0, t1          # G 的格子
        la    t1, g_tab
        add   t1, t1, t0
        lbu   t3, 0(t1)           # t3 = G 表查到的值

        # a0 = max(t2, t3)
        mv    a0, t2
        bgeu  t2, t3, heur_done   # t2 已經比較大 → 直接回傳
        mv    a0, t3              # 否則回傳 t3
heur_done:
        ret

invalid:
        la    a0, msg_bad
        li    a7, 4
        ecall
        li    a7, 10
        ecall
