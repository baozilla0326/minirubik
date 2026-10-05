/* ida.c: host-side experiment for an IDA* solver of the 2x2x2 cube.
 *
 * Step 1:  transition tables for the permutation and orientation coordinates.
 * Step 2:  one distance table per coordinate (pattern databases A and B).
 * Step 2b: finer pattern tables D and G, built from the exact BFS table.
 * Step 3:  iterative IDA* with h = max(D, G).
 * Step 4:  host-side gates H1 and H3 against the exact table.
 *
 * Usage: ./ida [STATE] | --gates | --h3 | --compare
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { CUBIES = 7, PERMUTATIONS = 5040, ORIENTATIONS = 729, FACES = 3 };

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

/* Copied from solver.c: where each position takes its cubie from, and the
 * twist added on the way, for a clockwise quarter turn of R, B and D. */
static const uint8_t source[FACES][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[FACES][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

static state_t quarter_turn(state_t s, uint8_t face)
{
    state_t r;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t from = source[face][i];
        r.p[i] = s.p[from];
        r.o[i] = (uint8_t) ((s.o[from] + twist[face][i]) % 3);
    }
    return r;
}

/* Permutation rank: Lehmer code, 0 .. 5039. */
static uint16_t perm_rank(const state_t *s)
{
    uint16_t r = 0;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0;
        for (uint8_t j = i + 1; j < CUBIES; ++j)
            if (s->p[j] < s->p[i])
                ++smaller;
        r = (uint16_t) (r * (CUBIES - i) + smaller);
    }
    return r;
}

static void perm_unrank(uint16_t r, state_t *s)
{
    static const uint16_t fact[CUBIES] = {720, 120, 24, 6, 2, 1, 1};
    uint8_t avail[CUBIES] = {0, 1, 2, 3, 4, 5, 6};
    uint8_t left = CUBIES;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        uint8_t q = (uint8_t) (r / fact[i]);
        r %= fact[i];
        s->p[i] = avail[q];
        for (uint8_t j = q; j + 1 < left; ++j)
            avail[j] = avail[j + 1];
        --left;
    }
}

/* Orientation rank: first six twists as a base-3 number, 0 .. 728. */
static uint16_t ori_rank(const state_t *s)
{
    uint16_t r = 0;
    for (uint8_t i = 0; i < 6; ++i)
        r = (uint16_t) (r * 3 + s->o[i]);
    return r;
}

static void ori_unrank(uint16_t r, state_t *s)
{
    uint8_t sum = 0;
    for (int i = 5; i >= 0; --i) {
        s->o[i] = (uint8_t) (r % 3);
        sum = (uint8_t) (sum + s->o[i]);
        r /= 3;
    }
    s->o[6] = (uint8_t) ((3 - sum % 3) % 3);
}

/* ---- Step 1: transition tables (quarter turn of each face) ---- */
static uint16_t perm_move[FACES][PERMUTATIONS];
static uint16_t ori_move[FACES][ORIENTATIONS];

static void build_moves(void)
{
    state_t s;
    memset(&s, 0, sizeof s);
    for (uint16_t r = 0; r < PERMUTATIONS; ++r) {
        perm_unrank(r, &s);
        for (uint8_t f = 0; f < FACES; ++f) {
            state_t n = quarter_turn(s, f);
            perm_move[f][r] = perm_rank(&n);
        }
    }
    for (uint8_t i = 0; i < CUBIES; ++i)
        s.p[i] = i;
    for (uint16_t r = 0; r < ORIENTATIONS; ++r) {
        ori_unrank(r, &s);
        for (uint8_t f = 0; f < FACES; ++f) {
            state_t n = quarter_turn(s, f);
            ori_move[f][r] = ori_rank(&n);
        }
    }
}

/* ---- Step 2: distance tables by BFS from the solved coordinate ---- */
static uint8_t perm_dist[PERMUTATIONS];
static uint8_t ori_dist[ORIENTATIONS];

/* move points at a FACES x n table; dist receives n distances. */
static void build_dist(const uint16_t *move, uint16_t n, uint8_t *dist)
{
    static uint16_t queue[PERMUTATIONS];
    uint16_t head = 0, tail = 0;
    memset(dist, 0xFF, n);
    dist[0] = 0;
    queue[tail++] = 0;
    while (head < tail) {
        uint16_t here = queue[head++];
        for (uint8_t f = 0; f < FACES; ++f) {
            uint16_t next = here;
            for (uint8_t t = 0; t < 3; ++t) {
                next = move[f * n + next];
                if (dist[next] == 0xFF) {
                    dist[next] = (uint8_t) (dist[here] + 1);
                    queue[tail++] = next;
                }
            }
        }
    }
}

/* Print how many entries sit at each distance; return 0 if any is missing. */
static int report(const char *name, const uint8_t *dist, uint16_t n)
{
    unsigned count[16] = {0}, missing = 0, max = 0;
    for (uint16_t i = 0; i < n; ++i) {
        if (dist[i] == 0xFF) {
            ++missing;
            continue;
        }
        ++count[dist[i]];
        if (dist[i] > max)
            max = dist[i];
    }
    printf("%s: %u entries, solved = %u, max = %u, missing = %u\n", name, n,
           dist[0], max, missing);
    for (unsigned d = 0; d <= max; ++d)
        printf("  distance %2u: %4u\n", d, count[d]);
    return missing == 0;
}

/* ---- Step 2b: finer pattern tables D and G ---- */
enum { STATES = PERMUTATIONS * ORIENTATIONS };

/* Exact distance of every state, by BFS over the composite rank. Host only:
 * used to build D and G and as the reference for the gates. */
static uint8_t *build_exact(void)
{
    uint8_t *dist = malloc(STATES);
    uint32_t *queue = malloc((size_t) STATES * sizeof *queue);
    uint32_t head = 0, tail = 0;
    if (!dist || !queue) {
        free(dist);
        free(queue);
        return NULL;
    }
    memset(dist, 0xFF, STATES);
    dist[0] = 0;
    queue[tail++] = 0;
    while (head < tail) {
        uint32_t here = queue[head++];
        uint16_t p = (uint16_t) (here / ORIENTATIONS);
        uint16_t o = (uint16_t) (here % ORIENTATIONS);
        for (uint8_t f = 0; f < FACES; ++f) {
            uint16_t np = p, no = o;
            for (uint8_t t = 0; t < 3; ++t) {
                np = perm_move[f][np];
                no = ori_move[f][no];
                uint32_t there = (uint32_t) np * ORIENTATIONS + no;
                if (dist[there] == 0xFF) {
                    dist[there] = (uint8_t) (dist[here] + 1);
                    queue[tail++] = there;
                }
            }
        }
    }
    free(queue);
    return dist;
}

/* Pair coordinate: where cubies 0 and 1 sit and how they are twisted.
 * c_k = pos_k * 3 + twist_k (0..20), q = c_0 * 21 + c_1 (0..440). */
enum { PAIR = 441 };
static uint16_t pair_move[FACES][PAIR];

static uint16_t pair_of(const state_t *s)
{
    uint8_t c[2] = {0, 0};
    for (uint8_t i = 0; i < CUBIES; ++i)
        if (s->p[i] < 2)
            c[s->p[i]] = (uint8_t) (i * 3 + s->o[i]);
    return (uint16_t) (c[0] * 21 + c[1]);
}

static void build_pair_moves(void)
{
    for (uint16_t q = 0; q < PAIR; ++q) {
        uint8_t c0 = (uint8_t) (q / 21), c1 = (uint8_t) (q % 21);
        uint8_t pos0 = c0 / 3, pos1 = c1 / 3;
        if (pos0 == pos1)
            continue; /* two cubies cannot share a position */
        state_t s;
        uint8_t filler = 2;
        for (uint8_t i = 0; i < CUBIES; ++i) {
            s.o[i] = 0;
            s.p[i] = i == pos0 ? 0 : i == pos1 ? 1 : filler++;
        }
        s.o[pos0] = c0 % 3;
        s.o[pos1] = c1 % 3;
        for (uint8_t f = 0; f < FACES; ++f) {
            state_t n = quarter_turn(s, f);
            pair_move[f][q] = pair_of(&n);
        }
    }
}

/* D: every twist (orientation rank) + positions of cubies 0 and 1.
 * G: whole permutation (permutation rank) + twists of cubies 0 and 1. */
enum { D_SIZE = ORIENTATIONS * 49, G_SIZE = PERMUTATIONS * 9 };
static uint8_t d_tab[D_SIZE], g_tab[G_SIZE];

static uint32_t d_index(uint16_t o, uint16_t q)
{
    return (uint32_t) o * 49 + (q / 21 / 3) * 7 + (q % 21 / 3);
}

static uint32_t g_index(uint16_t p, uint16_t q)
{
    return (uint32_t) p * 9 + (q / 21 % 3) * 3 + (q % 21 % 3);
}

/* Each entry is the smallest true distance among all states that share its
 * index. A state is in its own set, so the entry never exceeds its distance. */
static void build_dg(const uint8_t *dist)
{
    memset(d_tab, 0xFF, sizeof d_tab);
    memset(g_tab, 0xFF, sizeof g_tab);
    state_t s;
    for (uint32_t r = 0; r < STATES; ++r) {
        uint16_t p = (uint16_t) (r / ORIENTATIONS);
        uint16_t o = (uint16_t) (r % ORIENTATIONS);
        perm_unrank(p, &s);
        ori_unrank(o, &s);
        uint16_t q = pair_of(&s);
        uint32_t di = d_index(o, q), gi = g_index(p, q);
        if (dist[r] < d_tab[di])
            d_tab[di] = dist[r];
        if (dist[r] < g_tab[gi])
            g_tab[gi] = dist[r];
    }
}

/* ---- Step 3: IDA* search, iterative (no recursion) ---- */
enum { MAX_DEPTH = 11, MOVES = 9 };

static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};
static unsigned long nodes; /* states generated during the last search */

/* Which tables the heuristic uses: bit 0 picks D over A, bit 1 picks G over
 * B. The default, 3, is max(D, G); the others exist for --compare. */
static int use_tables = 3;

/* h = the larger of the two pattern-table lower bounds. */
static uint8_t heuristic(uint16_t p, uint16_t o, uint16_t q)
{
    uint8_t a = (use_tables & 1) ? d_tab[d_index(o, q)] : ori_dist[o];
    uint8_t b = (use_tables & 2) ? g_tab[g_index(p, q)] : perm_dist[p];
    return a > b ? a : b;
}

/* Fill path[] with a shortest solution and return its length. */
static int ida(uint16_t p0, uint16_t o0, uint16_t q0, uint8_t *path)
{
    /* state at each depth, and the next move to try there */
    uint16_t p[MAX_DEPTH + 1], o[MAX_DEPTH + 1], q[MAX_DEPTH + 1];
    uint8_t next[MAX_DEPTH + 1];

    nodes = 1;
    if (heuristic(p0, o0, q0) == 0)
        return 0; /* already solved */
    p[0] = p0;
    o[0] = o0;
    q[0] = q0;
    for (int bound = heuristic(p0, o0, q0); bound <= MAX_DEPTH; ++bound) {
        int d = 0;
        next[0] = 0;
        while (d >= 0) {
            if (next[d] == MOVES) { /* every move tried here: back up */
                --d;
                continue;
            }
            uint8_t m = next[d]++;
            uint8_t face = m / 3;
            if (d > 0 && face == path[d - 1] / 3)
                continue; /* same face twice in a row is never shortest */
            uint16_t np = p[d], no = o[d], nq = q[d];
            for (uint8_t t = 0; t <= m % 3; ++t) {
                np = perm_move[face][np];
                no = ori_move[face][no];
                nq = pair_move[face][nq];
            }
            ++nodes;
            uint8_t h = heuristic(np, no, nq);
            if (d + 1 + h > bound)
                continue; /* cannot finish within this bound: prune */
            path[d] = m;
            if (h == 0)
                return d + 1; /* solved */
            ++d;
            p[d] = np;
            o[d] = no;
            q[d] = nq;
            next[d] = 0;
        }
    }
    return -1; /* not reached for a valid cube */
}

/* Parse a 14-digit state; return 0 if it is not a valid cube. */
static int parse(const char *in, state_t *s)
{
    uint8_t sum = 0, seen = 0;
    for (int i = 0; i < 14; ++i) {
        int limit = i < CUBIES ? CUBIES : 3;
        if (in[i] < '1' || in[i] > '0' + limit)
            return 0;
        uint8_t v = (uint8_t) (in[i] - '1');
        if (i < CUBIES) {
            if (seen & (1u << v))
                return 0; /* cubie repeated */
            seen |= (uint8_t) (1u << v);
            s->p[i] = v;
        } else {
            s->o[i - CUBIES] = v;
            sum = (uint8_t) (sum + v);
        }
    }
    return in[14] == '\0' && sum % 3 == 0;
}

/* Apply the moves to the state and check that it ends solved. */
static int check(state_t s, const uint8_t *path, int len)
{
    for (int i = 0; i < len; ++i)
        for (uint8_t t = 0; t <= path[i] % 3; ++t)
            s = quarter_turn(s, path[i] / 3);
    for (uint8_t i = 0; i < CUBIES; ++i)
        if (s.p[i] != i || s.o[i] != 0)
            return 0;
    return 1;
}

/* ---- Step 4: host-side gates against the exact BFS distance table ---- */

/* Does path bring (p, o) back to the solved coordinates (0, 0)? */
static int reaches_solved(uint16_t p, uint16_t o, const uint8_t *path, int len)
{
    for (int i = 0; i < len; ++i)
        for (uint8_t t = 0; t <= path[i] % 3; ++t) {
            p = perm_move[path[i] / 3][p];
            o = ori_move[path[i] / 3][o];
        }
    return p == 0 && o == 0;
}

/* Coordinates of the state with this composite rank. */
static void coords(uint32_t r, uint16_t *p, uint16_t *o, uint16_t *q)
{
    state_t s;
    *p = (uint16_t) (r / ORIENTATIONS);
    *o = (uint16_t) (r % ORIENTATIONS);
    perm_unrank(*p, &s);
    ori_unrank(*o, &s);
    *q = pair_of(&s);
}

/* H1 over every state; the search over every distance-11 state; and, when
 * full is set, H3 over every state. Returns 0 if all checks pass. */
static int run_gates(const uint8_t *dist, int full)
{
    int bad = 0;
    uint16_t p, o, q;

    /* H1: the heuristic never exceeds the true distance. */
    unsigned long h1_fail = 0;
    for (uint32_t r = 0; r < STATES; ++r) {
        coords(r, &p, &o, &q);
        if (heuristic(p, o, q) > dist[r])
            ++h1_fail;
    }
    printf("H1 admissibility: %lu violations over %u states\n", h1_fail,
           STATES);
    bad |= h1_fail != 0;

    /* Search cost over the hardest states, or over all states for H3. */
    unsigned long worst = 0, total = 0, count = 0, wrong = 0;
    uint32_t worst_rank = 0;
    uint8_t path[MAX_DEPTH];
    for (uint32_t r = 0; r < STATES; ++r) {
        if (!full && dist[r] != 11)
            continue;
        coords(r, &p, &o, &q);
        int len = ida(p, o, q, path);
        if (len != dist[r] || !reaches_solved(p, o, path, len))
            ++wrong;
        if (dist[r] == 11) {
            ++count;
            total += nodes;
            if (nodes > worst) {
                worst = nodes;
                worst_rank = r;
            }
        }
    }
    printf("%s: %lu wrong\n",
           full ? "H3 optimality over all states"
                : "distance-11 states solved optimally",
           wrong);
    printf("distance-11 states: %lu, nodes max %lu, mean %lu\n", count, worst,
           count ? total / count : 0);

    /* Print the worst state as a 14-digit input. */
    state_t s;
    perm_unrank((uint16_t) (worst_rank / ORIENTATIONS), &s);
    ori_unrank((uint16_t) (worst_rank % ORIENTATIONS), &s);
    printf("worst state: ");
    for (int i = 0; i < CUBIES; ++i)
        putchar('1' + s.p[i]);
    for (int i = 0; i < CUBIES; ++i)
        putchar('1' + s.o[i]);
    putchar('\n');

    bad |= wrong != 0;
    return bad;
}

/* Largest entry of a pattern table, skipping slots no state maps to. */
static unsigned table_max(const uint8_t *tab, uint32_t n)
{
    unsigned max = 0;
    for (uint32_t i = 0; i < n; ++i)
        if (tab[i] != 0xFF && tab[i] > max)
            max = tab[i];
    return max;
}

int main(int argc, char **argv)
{
    build_moves();
    build_dist(&ori_move[0][0], ORIENTATIONS, ori_dist);
    build_dist(&perm_move[0][0], PERMUTATIONS, perm_dist);
    int ok = report("orientation", ori_dist, ORIENTATIONS);
    ok &= report("permutation", perm_dist, PERMUTATIONS);
    if (!ok)
        return 1;

    build_pair_moves();
    uint8_t *dist = build_exact();
    if (!dist) {
        fputs("out of memory\n", stderr);
        return 1;
    }
    build_dg(dist);
    state_t solved;
    perm_unrank(0, &solved);
    ori_unrank(0, &solved);
    uint16_t q_solved = pair_of(&solved);
    printf("D: %u bytes, solved = %u, max = %u\n", (unsigned) D_SIZE,
           d_tab[d_index(0, q_solved)], table_max(d_tab, D_SIZE));
    printf("G: %u bytes, solved = %u, max = %u\n", (unsigned) G_SIZE,
           g_tab[g_index(0, q_solved)], table_max(g_tab, G_SIZE));

    int rc = 0;
    if (argc > 1 && !strcmp(argv[1], "--gates")) {
        rc = run_gates(dist, 0); /* H1 + every distance-11 state */
    } else if (argc > 1 && !strcmp(argv[1], "--h3")) {
        rc = run_gates(dist, 1); /* H1 + H3 over every state (minutes) */
    } else if (argc > 1 && !strcmp(argv[1], "--compare")) {
        static const char *const name[4] = {"max(A, B)", "max(D, B)",
                                            "max(A, G)", "max(D, G)"};
        for (use_tables = 0; use_tables < 4; ++use_tables) {
            printf("== h = %s\n", name[use_tables]);
            rc |= run_gates(dist, 0);
        }
    } else {
        const char *input = argc > 1 ? argv[1] : "21345671111111";
        state_t s;
        if (!parse(input, &s)) {
            fprintf(stderr, "invalid state: %s\n", input);
            free(dist);
            return 2;
        }
        uint8_t path[MAX_DEPTH];
        int len = ida(perm_rank(&s), ori_rank(&s), pair_of(&s), path);
        printf("%s:", input);
        for (int i = 0; i < len; ++i)
            printf(" %s", move_names[path[i]]);
        printf("\n  length %d, nodes %lu, %s\n", len, nodes,
               check(s, path, len) ? "solves the cube" : "DOES NOT SOLVE");
    }
    free(dist);
    return rc;
}
