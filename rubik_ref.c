/* rubik_ref.c: compiler reference build of the final search, for comparison
 * with the hand-written RV32I assembly. Same algorithm and tables as
 * ida_fast() in ida.c: IDA* with h = max(D, G).
 *
 * Build (no libc, no libgcc, so a stray multiply or divide fails to link):
 *   riscv64-unknown-elf-gcc -O2 -march=rv32i -mabi=ilp32 -ffreestanding \
 *       -nostdlib -nostartfiles -static -o rubik_ref.elf rubik_ref.c
 * Run on Ripes:
 *   Ripes --mode cli --src rubik_ref.elf -t elf --proc RV32_ISS --iret
 */
#include <stdint.h>

#include "tables.h"

#ifndef INPUT
#define INPUT "21345671111111"
#endif

enum { CUBIES = 7, FACES = 3, MAX_DEPTH = 11 };

static const char input[] = INPUT;
static const char *const move_names[9] = {"R",  "R2", "R'", "B", "B2",
                                          "B'", "D",  "D2", "D'"};

/* ---- Ripes environment calls ---- */
static void ecall_str(const char *s)
{
    register const char *a0 __asm__("a0") = s;
    register int a7 __asm__("a7") = 4;
    __asm__ volatile("ecall" : : "r"(a0), "r"(a7) : "memory");
}

static void __attribute__((noreturn)) ecall_exit(int code)
{
    register int a0 __asm__("a0") = code;
    register int a7 __asm__("a7") = 93;
    __asm__ volatile("ecall" : : "r"(a0), "r"(a7) : "memory");
    for (;;)
        ;
}

/* gcc may emit calls to these even in freestanding code. */
void *memset(void *d, int c, unsigned long n)
{
    unsigned char *p = d;
    while (n--)
        *p++ = (unsigned char) c;
    return d;
}

void *memcpy(void *d, const void *s, unsigned long n)
{
    unsigned char *p = d;
    const unsigned char *q = s;
    while (n--)
        *p++ = *q++;
    return d;
}

/* ---- search: the same as ida_fast() ---- */
static uint8_t heuristic(uint16_t p, uint16_t o, uint16_t q)
{
    uint8_t a = d_tab[o * 49 + pair_pos[q]];
    uint8_t b = g_tab[p * 9 + pair_twist[q]];
    return a > b ? a : b;
}

static int ida(uint16_t p0, uint16_t o0, uint16_t q0, uint8_t *path)
{
    uint16_t p[MAX_DEPTH + 1], o[MAX_DEPTH + 1], q[MAX_DEPTH + 1];
    uint8_t face[MAX_DEPTH], turn[MAX_DEPTH], next_face[MAX_DEPTH];

    uint8_t h0 = heuristic(p0, o0, q0);
    if (h0 == 0)
        return 0;
    p[0] = p0;
    o[0] = o0;
    q[0] = q0;
    for (int bound = h0; bound <= MAX_DEPTH; ++bound) {
        int d = 0;
        next_face[0] = 0;
        turn[0] = 2;
        while (d >= 0) {
            if (turn[d] == 2) {
                uint8_t f = next_face[d];
                if (d > 0 && f == face[d - 1])
                    ++f;
                if (f == FACES) {
                    --d;
                    continue;
                }
                face[d] = f;
                next_face[d] = (uint8_t) (f + 1);
                turn[d] = 0;
                p[d + 1] = p[d];
                o[d + 1] = o[d];
                q[d + 1] = q[d];
            } else {
                ++turn[d];
            }
            uint8_t f = face[d];
            p[d + 1] = perm_move[f][p[d + 1]];
            o[d + 1] = ori_move[f][o[d + 1]];
            q[d + 1] = pair_move[f][q[d + 1]];
            uint8_t h = heuristic(p[d + 1], o[d + 1], q[d + 1]);
            if (d + 1 + h > bound)
                continue;
            path[d] = (uint8_t) (f * 3 + turn[d]);
            if (h == 0)
                return d + 1;
            ++d;
            next_face[d] = 0;
            turn[d] = 2;
        }
    }
    return -1;
}

/* ---- input: parse, validate, and compute the three coordinates ---- */
static int parse(uint16_t *pp, uint16_t *po, uint16_t *pq)
{
    uint8_t perm[CUBIES], ori[CUBIES];
    unsigned seen = 0, sum = 0;
    for (int i = 0; i < CUBIES; ++i) {
        unsigned v = (unsigned) (input[i] - '1');
        if (v >= CUBIES || (seen & (1u << v)))
            return 0;
        seen |= 1u << v;
        perm[i] = (uint8_t) v;
    }
    for (int i = 0; i < CUBIES; ++i) {
        unsigned v = (unsigned) (input[CUBIES + i] - '1');
        if (v >= 3)
            return 0;
        ori[i] = (uint8_t) v;
        sum += v;
    }
    while (sum >= 3)
        sum -= 3;
    if (input[2 * CUBIES] != '\0' || sum != 0)
        return 0;

    /* Lehmer rank by Horner's rule. Every step multiplies by a constant, which
     * the compiler turns into shifts and adds; a variable product such as
     * smaller * weight[i] would need __mulsi3. */
    unsigned c_less[CUBIES - 1];
    for (int i = 0; i < CUBIES - 1; ++i) {
        unsigned smaller = 0;
        for (int j = i + 1; j < CUBIES; ++j)
            smaller += perm[j] < perm[i];
        c_less[i] = smaller;
    }
    unsigned p = c_less[0];
    p = p * 6 + c_less[1];
    p = p * 5 + c_less[2];
    p = p * 4 + c_less[3];
    p = p * 3 + c_less[4];
    p = p * 2 + c_less[5];
    unsigned o = 0;
    for (int i = 0; i < CUBIES - 1; ++i)
        o = o * 3 + ori[i];
    unsigned c[2] = {0, 0};
    for (int i = 0; i < CUBIES; ++i)
        if (perm[i] < 2)
            c[perm[i]] = (unsigned) i * 3 + ori[i];
    *pp = (uint16_t) p;
    *po = (uint16_t) o;
    *pq = (uint16_t) (c[0] * 21 + c[1]);
    return 1;
}

/* T5: apply the path with the move tables and check it reaches (0, 0). */
static int reaches_solved(uint16_t p, uint16_t o, const uint8_t *path, int len)
{
    for (int i = 0; i < len; ++i) {
        uint8_t f = 0, t = path[i];
        while (t >= 3) {
            t -= 3;
            ++f;
        }
        for (uint8_t k = 0; k <= t; ++k) {
            p = perm_move[f][p];
            o = ori_move[f][o];
        }
    }
    return p == 0 && o == 0;
}

void __attribute__((noreturn, section(".text.start"))) _start(void)
{
    uint16_t p, o, q;
    if (!parse(&p, &o, &q)) {
        ecall_str("invalid state\n");
        ecall_exit(2);
    }
    uint8_t path[MAX_DEPTH];
    int len = ida(p, o, q, path);
    for (int i = 0; i < len; ++i) {
        ecall_str(move_names[path[i]]);
        ecall_str(" ");
    }
    ecall_str("\n");
    ecall_exit(reaches_solved(p, o, path, len) ? 0 : 1);
}
