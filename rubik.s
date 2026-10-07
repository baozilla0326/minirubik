# rubik.s: optimal 2x2x2 solver in RV32I (no M extension)

        .data
        .equ  EXPECT, 11              # 預期的最短步數（測資用）
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
# RENDER-BEGIN
        .equ  DELAY, 30000            # 每一步之間空轉幾圈
fl_tab:                               # 24 格貼紙：x, y, 位置, 第幾張貼紙
        .byte 9, 0, 7, 0,   13, 0, 4, 0,   9, 3, 0, 0,   13, 3, 1, 0
        .byte 0, 7, 7, 2,   4, 7, 0, 1,    9, 7, 0, 2,   13, 7, 1, 1
        .byte 18, 7, 1, 2,  22, 7, 4, 1,   27, 7, 4, 2,  31, 7, 7, 1
        .byte 0, 10, 6, 1,  4, 10, 3, 2,   9, 10, 3, 1,  13, 10, 2, 2
        .byte 18, 10, 2, 1, 22, 10, 5, 2,  27, 10, 5, 1, 31, 10, 6, 2
        .byte 9, 14, 3, 0,  13, 14, 2, 0,  9, 17, 6, 0,  13, 17, 5, 0
cub_col:                              # 角塊 0～7 的三張貼紙各屬於哪一面
        .byte 0, 5, 2,  0, 2, 4,  1, 4, 2,  1, 2, 5
        .byte 0, 4, 3,  1, 3, 4,  1, 5, 3,  0, 3, 5
src_tab:                              # solver.c 的 source[3][7]
        .byte 1, 4, 2, 0, 3, 5, 6
        .byte 0, 1, 2, 4, 5, 6, 3
        .byte 0, 2, 5, 3, 1, 4, 6
tw_tab:                               # solver.c 的 twist[3][7]
        .byte 1, 2, 0, 2, 1, 0, 0
        .byte 0, 0, 0, 1, 2, 1, 2
        .byte 0, 0, 0, 0, 0, 0, 0
new_p:   .zero   7
new_o:   .zero   7
        .align 2
face_rgb:                             # U 白、D 黃、F 綠、B 藍、R 紅、L 橘
        .word 0xFFFFFF, 0xFFFF00, 0x00FF00, 0x0000FF, 0xFF0000, 0xFF8000
# RENDER-END
        .align 2
row_perm: .word 0, 10080, 20160        # 每一面那一列在 perm_move 裡的位移（bytes）
row_ori:  .word 0, 1458, 2916
row_pair: .word 0, 882, 1764
msg_bad: .string "invalid state\n"
msg_fail: .string "FAIL\n"

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
        # v2：搜尋過程中位址不會變，所以只在這裡載入一次，之後用「暫存器 + 位移」。
        # s7 → 每一層的資料：st_p +0, st_o +24, st_q +48, face +72, turn +84, nextf +96, path +108
        # s8 → 列位移表：row_perm +0, row_ori +12, row_pair +24
        # s0 → pair_pos（pair_twist 緊接在後，+441）
        la    s7, st_p
        la    s8, row_perm
        la    s9, perm_move
        la    s10, ori_move
        la    s11, pair_move
        la    s0, pair_pos
        la    a6, d_tab
        la    a7, g_tab
        sh    s2, 0(s7)           # st_p[0] = p
        sh    s1, 24(s7)          # st_o[0] = o
        sh    s3, 48(s7)          # st_q[0] = q
        mv    a0, s2
        mv    a1, s1
        mv    a2, s3
        jal   ra, heur
        mv    s4, a0              # s4 = bound = h(起點)
        li    s6, 0               # s6 = 解答長度
        beqz  s4, found           # h = 0：已經解好

bound_loop:
        li    s5, 0               # s5 = d = 0
        sb    zero, 96(s7)        # nextf[0] = 0
        li    t1, 2
        sb    t1, 84(s7)          # turn[0] = 2（要開始新的一面）

node_loop:
        bltz  s5, next_bound      # d < 0：這一輪全部試完
        add   t0, s7, s5          # t0 = s7 + d（byte 陣列用）
        lbu   t1, 84(t0)          # t1 = turn[d]
        li    t2, 2
        bne   t1, t2, same_face   # 還沒轉滿 → 同一面再轉 90°

        # --- 開始新的一面 ---
        lbu   t3, 96(t0)          # t3 = f = nextf[d]
        beqz  s5, face_ok         # d = 0：沒有上一步
        lbu   t4, 71(t0)          # t4 = face[d-1]（72 - 1）
        bne   t3, t4, face_ok
        addi  t3, t3, 1           # 同一面不連轉：跳過
face_ok:
        li    t2, 3
        bne   t3, t2, face_go
        addi  s5, s5, -1          # 三面都試完：退回上一層
        j     node_loop
face_go:
        sb    t3, 72(t0)          # face[d] = f
        addi  t4, t3, 1
        sb    t4, 96(t0)          # nextf[d] = f + 1
        sb    zero, 84(t0)        # turn[d] = 0
        slli  t5, s5, 1
        add   t5, s7, t5          # t5 = s7 + 2d（halfword 陣列用）
        lhu   t1, 0(t5)
        sh    t1, 2(t5)           # st_p[d+1] = st_p[d]
        lhu   t1, 24(t5)
        sh    t1, 26(t5)          # st_o[d+1] = st_o[d]
        lhu   t1, 48(t5)
        sh    t1, 50(t5)          # st_q[d+1] = st_q[d]
        j     apply_turn

same_face:
        addi  t1, t1, 1
        sb    t1, 84(t0)          # turn[d] += 1

apply_turn:
        # 第 d+1 層的方塊再轉 90°：三張轉移表各查一次
        add   t0, s7, s5
        lbu   t3, 72(t0)          # t3 = f
        slli  t3, t3, 2
        add   t3, s8, t3          # t3 = &row_perm[f]
        slli  t5, s5, 1
        add   t5, s7, t5          # t5 = s7 + 2d

        lw    t0, 0(t3)           # perm_move 第 f 列的位移
        add   t0, t0, s9
        lhu   t2, 2(t5)           # st_p[d+1]
        slli  t2, t2, 1
        add   t2, t0, t2
        lhu   a0, 0(t2)           # a0 = 新的 p
        sh    a0, 2(t5)

        lw    t0, 12(t3)          # ori_move 第 f 列的位移
        add   t0, t0, s10
        lhu   t2, 26(t5)          # st_o[d+1]
        slli  t2, t2, 1
        add   t2, t0, t2
        lhu   a1, 0(t2)           # a1 = 新的 o
        sh    a1, 26(t5)

        lw    t0, 24(t3)          # pair_move 第 f 列的位移
        add   t0, t0, s11
        lhu   t2, 50(t5)          # st_q[d+1]
        slli  t2, t2, 1
        add   t2, t0, t2
        lhu   a2, 0(t2)           # a2 = 新的 q
        sh    a2, 50(t5)

        jal   ra, heur            # a0 = h
        addi  t0, s5, 1
        add   t0, t0, a0          # d + 1 + h
        bltu  s4, t0, node_loop   # > bound：剪枝

        # path[d] = f × 3 + turn[d]
        add   t0, s7, s5
        lbu   t1, 72(t0)          # f
        slli  t2, t1, 1
        add   t1, t1, t2          # f × 3
        lbu   t2, 84(t0)          # turn[d]
        add   t1, t1, t2
        sb    t1, 108(t0)         # path[d]

        addi  s5, s5, 1           # d + 1
        beqz  a0, solved          # h = 0：解好了
        sb    zero, 97(t0)        # nextf[d+1] = 0（t0 還是舊的 s7 + d）
        li    t1, 2
        sb    t1, 85(t0)          # turn[d+1] = 2
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

        # ===== 4.5：驗證答案（T5）=====
        mv    a0, s2              # a0 = 起點的 p
        mv    a1, s1              # a1 = 起點的 o
        li    s8, 0               # s8 = 第幾步
verify_step:
        bgeu  s8, s6, verify_check   # 所有步都轉完了 → 檢查
        la    t0, path
        add   t0, t0, s8
        lbu   t1, 0(t0)           # t1 = 轉法編號 m
        li    t2, 0               # t2 = 面 f
verify_div:
        li    t3, 3
        bltu  t1, t3, verify_turn
        addi  t1, t1, -3          # m -= 3
        addi  t2, t2, 1           # f += 1
        j     verify_div
verify_turn:
        slli  t2, t2, 2           # f × 4（row 表每格 4 bytes）
        addi  t1, t1, 1           # 要轉 m + 1 次 90°
verify_quarter:
        la    t3, row_perm        # p = perm_move[f][p]
        add   t3, t3, t2
        lw    t3, 0(t3)
        la    t4, perm_move
        add   t3, t3, t4
        slli  t4, a0, 1
        add   t3, t3, t4
        lhu   a0, 0(t3)
        la    t3, row_ori         # o = ori_move[f][o]
        add   t3, t3, t2
        lw    t3, 0(t3)
        la    t4, ori_move
        add   t3, t3, t4
        slli  t4, a1, 1
        add   t3, t3, t4
        lhu   a1, 0(t3)
        addi  t1, t1, -1
        bnez  t1, verify_quarter
        addi  s8, s8, 1
        j     verify_step
verify_check:
        bnez  a0, fail            # p 不是 0 → 失敗
        bnez  a1, fail            # o 不是 0 → 失敗

        # ===== 測資檢查：長度必須等於預期 =====
        li    t0, EXPECT
        bne   s6, t0, fail

# RENDER-BEGIN
        # ===== LED 動畫：從打亂的方塊開始，照答案一步一步轉 =====
        jal   ra, render
        jal   ra, delay
        li    s8, 0
anim_step:
        bgeu  s8, s6, anim_done
        la    t0, path
        add   t0, t0, s8
        lbu   s9, 0(t0)           # s9 = 轉法編號 m
        li    s10, 0              # s10 = 面 f
anim_div:
        li    t0, 3
        bltu  s9, t0, anim_turns
        addi  s9, s9, -3
        addi  s10, s10, 1
        j     anim_div
anim_turns:
        addi  s9, s9, 1           # 轉 m + 1 次 90°
anim_quarter:
        mv    a0, s10
        jal   ra, qturn
        addi  s9, s9, -1
        bnez  s9, anim_quarter
        jal   ra, render          # 每轉完一步就重畫
        jal   ra, delay
        addi  s8, s8, 1
        j     anim_step
anim_done:
# RENDER-END

        li    a0, 0               # 全部通過：exit code 0
        li    a7, 93
        ecall

fail:
        la    a0, msg_fail
        li    a7, 4
        ecall
        li    a0, 1               # 失敗：exit code 1
        li    a7, 93
        ecall

# heur: a0 = p, a1 = o, a2 = q  →  a0 = h = max(D, G)
# Leaf function: calls nothing, uses only t registers, so no stack frame.
heur:
        # v2：表格位址已經在暫存器裡（s0 = pair_pos，a6 = d_tab，a7 = g_tab）
        slli  t0, a1, 5           # 32o
        slli  t1, a1, 4           # 16o
        add   t0, t0, t1
        add   t0, t0, a1          # 49o
        add   t1, s0, a2          # t1 = &pair_pos[q]
        lbu   t2, 0(t1)           # pair_pos[q]
        lbu   t3, 441(t1)         # pair_twist[q]（緊接在 pair_pos 後面）
        add   t0, t0, t2
        add   t0, t0, a6
        lbu   t2, 0(t0)           # t2 = D[o × 49 + pair_pos[q]]
        slli  t1, a0, 3           # 8p
        add   t1, t1, a0          # 9p
        add   t1, t1, t3
        add   t1, t1, a7
        lbu   t3, 0(t1)           # t3 = G[p × 9 + pair_twist[q]]
        mv    a0, t2              # a0 = max(t2, t3)
        bgeu  t2, t3, heur_done
        mv    a0, t3
heur_done:
        ret

# RENDER-BEGIN
# ===== LED：方塊展開圖 =====
# render：依照 cube_p / cube_o 畫出 24 格貼紙。
# Leaf function：只用 t0～t6、a2～a6，不呼叫別人。
render:
        li    a3, LED_MATRIX_0_BASE
        li    a4, LED_MATRIX_0_WIDTH
        slli  a4, a4, 2           # a4 = 一列 LED 的 bytes（WIDTH × 4）
        la    a5, fl_tab          # 每格貼紙 4 bytes：x, y, 位置, 第幾張貼紙
        li    a6, 24
r_face:
        lbu   t0, 0(a5)           # t0 = x
        lbu   t1, 1(a5)           # t1 = y
        lbu   t2, 2(a5)           # t2 = 位置（0 = 固定角）
        lbu   t3, 3(a5)           # t3 = 這個位置的第幾張貼紙 j
        li    t4, 0               # t4 = 角塊編號（固定角是 0）
        li    t5, 0               # t5 = 扭轉
        beqz  t2, r_have
        la    t6, cube_p
        add   t6, t6, t2
        lbu   t4, -1(t6)          # cube_p[位置 - 1]
        addi  t4, t4, 1           # 角塊編號 1～7
        la    t6, cube_o
        add   t6, t6, t2
        lbu   t5, -1(t6)          # cube_o[位置 - 1]
r_have:
        sub   t3, t3, t5          # k = j - 扭轉
        bgez  t3, r_k
        addi  t3, t3, 3           # mod 3：負的就加 3
r_k:
        slli  t6, t4, 1
        add   t6, t6, t4          # 角塊 × 3
        add   t6, t6, t3
        la    t5, cub_col
        add   t5, t5, t6
        lbu   t5, 0(t5)           # 這張貼紙原本屬於哪一面（0～5）
        slli  t5, t5, 2
        la    t6, face_rgb
        add   t6, t6, t5
        lw    a2, 0(t6)           # a2 = 顏色 0x00RRGGBB

        slli  t0, t0, 2
        add   t6, a3, t0          # t6 = BASE + x × 4
r_row:
        beqz  t1, r_draw          # 往下 y 列：加 y 次 stride，不用乘法
        add   t6, t6, a4
        addi  t1, t1, -1
        j     r_row
r_draw:
        li    t1, 3               # 每格 3 列 × 4 個 LED
r_line:
        sw    a2, 0(t6)
        sw    a2, 4(t6)
        sw    a2, 8(t6)
        sw    a2, 12(t6)
        add   t6, t6, a4
        addi  t1, t1, -1
        bnez  t1, r_line
        addi  a5, a5, 4
        addi  a6, a6, -1
        bnez  a6, r_face
        ret

# qturn：a0 = 面 f（0 = R, 1 = B, 2 = D），把 cube_p / cube_o 轉 90°。
# 跟 solver.c 的 quarter_turn 一樣：p'[i] = p[source[i]]，o'[i] = (o[source[i]] + twist[i]) mod 3
qturn:
        slli  t0, a0, 3
        sub   t0, t0, a0          # t0 = f × 7
        la    t1, src_tab
        add   t1, t1, t0
        la    t2, tw_tab
        add   t2, t2, t0
        li    t3, 0               # i
q_each:
        lbu   t4, 0(t1)           # from = source[f][i]
        la    t5, cube_p
        add   t5, t5, t4
        lbu   t6, 0(t5)           # cube_p[from]
        la    t5, new_p
        add   t5, t5, t3
        sb    t6, 0(t5)
        la    t5, cube_o
        add   t5, t5, t4
        lbu   t6, 0(t5)           # cube_o[from]
        lbu   t4, 0(t2)           # twist[f][i]
        add   t6, t6, t4          # 最多 2 + 2 = 4
        li    t4, 3
        bltu  t6, t4, q_mod_ok
        addi  t6, t6, -3          # mod 3：一次條件減法就夠
q_mod_ok:
        la    t5, new_o
        add   t5, t5, t3
        sb    t6, 0(t5)
        addi  t1, t1, 1
        addi  t2, t2, 1
        addi  t3, t3, 1
        li    t4, 7
        bltu  t3, t4, q_each
        li    t3, 0               # 把新的狀態抄回 cube_p / cube_o
q_copy:
        la    t5, new_p
        add   t5, t5, t3
        lbu   t6, 0(t5)
        la    t5, cube_p
        add   t5, t5, t3
        sb    t6, 0(t5)
        la    t5, new_o
        add   t5, t5, t3
        lbu   t6, 0(t5)
        la    t5, cube_o
        add   t5, t5, t3
        sb    t6, 0(t5)
        addi  t3, t3, 1
        li    t4, 7
        bltu  t3, t4, q_copy
        ret

# delay：空轉一下，讓動畫看得到
delay:
        li    t0, DELAY
d_loop:
        addi  t0, t0, -1
        bnez  t0, d_loop
        ret
# RENDER-END

invalid:
        la    a0, msg_bad
        li    a7, 4
        ecall
        li    a7, 10
        ecall
