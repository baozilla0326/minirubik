/* ida.c: host-side experiment for an IDA* solver of the 2x2x2 cube.
 *
 * Step 1: transition tables for the permutation and orientation coordinates.
 * Step 2: one distance table per coordinate (pattern databases), by BFS.
 */
#include <stdint.h>
#include <stdio.h>
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

/* ---- Step 3: IDA* search, iterative (no recursion) ---- */
enum { MAX_DEPTH = 11, MOVES = 9 };

static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};
static unsigned long nodes; /* states generated during the last search */

/* h = the larger of the two pattern-table lower bounds. */
static uint8_t heuristic(uint16_t p, uint16_t o)
{
    uint8_t hp = perm_dist[p], ho = ori_dist[o];
    return hp > ho ? hp : ho;
}

/* Fill path[] with a shortest solution and return its length. */
static int ida(uint16_t p0, uint16_t o0, uint8_t *path)
{
    uint16_t p[MAX_DEPTH + 1], o[MAX_DEPTH + 1]; /* state at each depth */
    uint8_t next[MAX_DEPTH + 1];                 /* next move to try */

    nodes = 1;
    if (heuristic(p0, o0) == 0)
        return 0; /* already solved */
    p[0] = p0;
    o[0] = o0;
    for (int bound = heuristic(p0, o0); bound <= MAX_DEPTH; ++bound) {
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
            uint16_t np = p[d], no = o[d];
            for (uint8_t t = 0; t <= m % 3; ++t) {
                np = perm_move[face][np];
                no = ori_move[face][no];
            }
            ++nodes;
            uint8_t h = heuristic(np, no);
            if (d + 1 + h > bound)
                continue; /* cannot finish within this bound: prune */
            path[d] = m;
            if (h == 0)
                return d + 1; /* solved */
            ++d;
            p[d] = np;
            o[d] = no;
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

int main(int argc, char **argv)
{
    build_moves();
    build_dist(&ori_move[0][0], ORIENTATIONS, ori_dist);
    build_dist(&perm_move[0][0], PERMUTATIONS, perm_dist);
    int ok = report("orientation", ori_dist, ORIENTATIONS);
    ok &= report("permutation", perm_dist, PERMUTATIONS);
    if (!ok)
        return 1;

    const char *input = argc > 1 ? argv[1] : "21345671111111";
    state_t s;
    if (!parse(input, &s)) {
        fprintf(stderr, "invalid state: %s\n", input);
        return 2;
    }
    uint8_t path[MAX_DEPTH];
    int len = ida(perm_rank(&s), ori_rank(&s), path);
    printf("%s:", input);
    for (int i = 0; i < len; ++i)
        printf(" %s", move_names[path[i]]);
    printf("\n  length %d, nodes %lu, %s\n", len, nodes,
           check(s, path, len) ? "solves the cube" : "DOES NOT SOLVE");
    return 0;
}
