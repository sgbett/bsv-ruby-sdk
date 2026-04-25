/* frozen_string_literal: true */
#include "secp256k1_native.h"

/*
 * jacobian.c — Jacobian point operations on the secp256k1 curve.
 *
 * Points are represented as three uint256_t values [X, Y, Z] in Jacobian
 * (homogeneous projective) coordinates.  The affine point (x, y) corresponds
 * to the Jacobian point (X, Y, Z) via:
 *
 *   x = X / Z²   and   y = Y / Z³
 *
 * The point at infinity is represented as [0, 1, 0] (Z = 0).
 *
 * All three functions (jp_double, jp_add, jp_neg) call the internal field
 * operations from field.c directly — no Ruby method dispatch occurs for
 * intermediate field arithmetic.  A single jp_double executes ~14 field
 * operations entirely in C; a single jp_add executes ~18.
 *
 * Formulae from hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html
 * (parameter a = 0 for secp256k1).
 *
 * Constant-time discipline
 * ------------------------
 * jp_double: The Y=0 (point at infinity) check is handled branchlessly by
 *   computing the full result and masking to JP_INFINITY when Y is zero.
 * jp_add: Branches on pz==0 / qz==0 / h==0 operate on public data in all
 *   call paths (the wNAF accumulator starts at infinity, which is public).
 *   The field arithmetic within the main computation path is branchless.
 * jp_neg: Branchless — delegates the zero-checking to fneg_internal.
 */

/* The point at infinity: [0, 1, 0] */
static const uint256_t JP_INF_X = {{ 0ULL, 0ULL, 0ULL, 0ULL }};
static const uint256_t JP_INF_Y = {{ 1ULL, 0ULL, 0ULL, 0ULL }};
static const uint256_t JP_INF_Z = {{ 0ULL, 0ULL, 0ULL, 0ULL }};

/* Small field element constants used in point formulae. */
static const uint256_t SMALL_2 = {{ 2ULL, 0ULL, 0ULL, 0ULL }};
static const uint256_t SMALL_3 = {{ 3ULL, 0ULL, 0ULL, 0ULL }};
static const uint256_t SMALL_4 = {{ 4ULL, 0ULL, 0ULL, 0ULL }};
static const uint256_t SMALL_8 = {{ 8ULL, 0ULL, 0ULL, 0ULL }};

/* Unpack a Ruby Array of 3 Integers into a uint256_t[3].
 * Indices: 0 = X, 1 = Y, 2 = Z. */
static void unpack_point(uint256_t out[3], VALUE rb_point)
{
    Check_Type(rb_point, T_ARRAY);
    if (RARRAY_LEN(rb_point) != 3) {
        rb_raise(rb_eArgError, "Jacobian point must be an Array of 3 integers [X, Y, Z]");
    }
    out[0] = rb_to_uint256(rb_ary_entry(rb_point, 0));
    out[1] = rb_to_uint256(rb_ary_entry(rb_point, 1));
    out[2] = rb_to_uint256(rb_ary_entry(rb_point, 2));
}

/* Pack a uint256_t[3] into a new Ruby Array of 3 Integers. */
static VALUE pack_point(const uint256_t r[3])
{
    VALUE result = rb_ary_new_capa(3);
    rb_ary_push(result, uint256_to_rb(&r[0]));
    rb_ary_push(result, uint256_to_rb(&r[1]));
    rb_ary_push(result, uint256_to_rb(&r[2]));
    return result;
}

/* -----------------------------------------------------------------------
 * Internal Jacobian point operations — called from Ruby-facing wrappers
 * and from each other.  No Ruby interaction occurs within these functions.
 * ----------------------------------------------------------------------- */

/*
 * jp_double_internal — double a Jacobian point.
 *
 * Formula (a=0 for secp256k1, from hyperelliptic.org):
 *
 *   Y1sq = Y1²
 *   S    = 4 · X1 · Y1sq
 *   M    = 3 · X1²
 *   X3   = M² - 2·S
 *   Y3   = M·(S - X3) - 8·Y1sq²
 *   Z3   = 2·Y1·Z1
 *
 * Special case: if Y1 = 0 the point is at infinity.  Handled branchlessly:
 * the full result is computed and then replaced by JP_INFINITY when Y1 is
 * zero (using a selection mask derived from uint256_is_zero).
 *
 * Matches the Ruby jp_double implementation exactly, including computation
 * order, so that wNAF cache entries produced by C are identical to those
 * produced by Ruby.
 */
void jp_double_internal(uint256_t r[3], const uint256_t p[3])
{
    uint256_t y1sq, s, m, x3, y3, z3;
    uint256_t tmp;

    /* y1sq = Y1² */
    fsqr_internal(&y1sq, &p[1]);

    /* s = 4 * (X1 * y1sq) */
    fmul_internal(&tmp, &p[0], &y1sq);
    fmul_internal(&s, &SMALL_4, &tmp);

    /* m = 3 * X1² */
    fsqr_internal(&tmp, &p[0]);
    fmul_internal(&m, &SMALL_3, &tmp);

    /* x3 = m² - 2*s */
    fsqr_internal(&tmp, &m);
    uint256_t two_s;
    fmul_internal(&two_s, &SMALL_2, &s);
    fsub_internal(&x3, &tmp, &two_s);

    /* y3 = m * (s - x3) - 8 * y1sq² */
    uint256_t s_minus_x3, y1sq_sq, eight_y1sq_sq;
    fsub_internal(&s_minus_x3, &s, &x3);
    fmul_internal(&tmp, &m, &s_minus_x3);
    fsqr_internal(&y1sq_sq, &y1sq);
    fmul_internal(&eight_y1sq_sq, &SMALL_8, &y1sq_sq);
    fsub_internal(&y3, &tmp, &eight_y1sq_sq);

    /* z3 = 2 * Y1 * Z1 */
    fmul_internal(&tmp, &p[1], &p[2]);
    fmul_internal(&z3, &SMALL_2, &tmp);

    /* Branchless infinity check: if Y1 == 0, result is [0, 1, 0].
     *
     * Compute mask = all 1s if Y1 is zero, all 0s otherwise.
     * Use the mask to select between [x3, y3, z3] and JP_INFINITY. */
    uint64_t is_zero = uint256_is_zero(&p[1]);
    uint64_t mask = -(uint64_t)(is_zero != 0); /* all 1s if Y1 == 0 */
    int i;
    for (i = 0; i < 4; i++) {
        r[0].d[i] = (x3.d[i] & ~mask) | (JP_INF_X.d[i] & mask);
        r[1].d[i] = (y3.d[i] & ~mask) | (JP_INF_Y.d[i] & mask);
        r[2].d[i] = (z3.d[i] & ~mask) | (JP_INF_Z.d[i] & mask);
    }
}

/*
 * jp_add_internal — add two Jacobian points.
 *
 * Formula (from hyperelliptic.org, "add-2007-bl"):
 *
 *   Z1Z1 = Z1²,  Z2Z2 = Z2²
 *   U1   = X1·Z2Z2,  U2 = X2·Z1Z1
 *   S1   = Y1·Z2·Z2Z2,  S2 = Y2·Z1·Z1Z1
 *   H    = U2 - U1
 *   R    = S2 - S1
 *   H2   = H²,  H3 = H·H2
 *   V    = U1·H2
 *   X3   = R² - H3 - 2·V
 *   Y3   = R·(V - X3) - S1·H3
 *   Z3   = H·Z1·Z2
 *
 * Special cases (handled with branches — all operate on public data):
 *   - pz == 0 (p is infinity)  → return q
 *   - qz == 0 (q is infinity)  → return p
 *   - h == 0, r == 0           → points are equal, call jp_double_internal(p)
 *   - h == 0, r != 0           → points are negatives of each other → infinity
 *
 * Matches the Ruby jp_add implementation exactly.
 */
void jp_add_internal(uint256_t r[3], const uint256_t p[3], const uint256_t q[3])
{
    /* Handle point-at-infinity cases (pz == 0 or qz == 0).
     * These branch on public data (Z coordinates are public in all call paths). */
    if (uint256_is_zero(&p[2])) {
        r[0] = q[0]; r[1] = q[1]; r[2] = q[2];
        return;
    }
    if (uint256_is_zero(&q[2])) {
        r[0] = p[0]; r[1] = p[1]; r[2] = p[2];
        return;
    }

    uint256_t z1z1, z2z2;
    uint256_t u1, u2;
    uint256_t s1, s2;
    uint256_t tmp;

    /* z1z1 = Z1²,  z2z2 = Z2² */
    fsqr_internal(&z1z1, &p[2]);
    fsqr_internal(&z2z2, &q[2]);

    /* u1 = X1 * z2z2,  u2 = X2 * z1z1 */
    fmul_internal(&u1, &p[0], &z2z2);
    fmul_internal(&u2, &q[0], &z1z1);

    /* s1 = Y1 * Z2 * z2z2,  s2 = Y2 * Z1 * z1z1 */
    fmul_internal(&tmp, &q[2], &z2z2);
    fmul_internal(&s1, &p[1], &tmp);

    fmul_internal(&tmp, &p[2], &z1z1);
    fmul_internal(&s2, &q[1], &tmp);

    /* h = u2 - u1,  r_val = s2 - s1 */
    uint256_t h, r_val;
    fsub_internal(&h, &u2, &u1);
    fsub_internal(&r_val, &s2, &s1);

    /* Handle the h == 0 special cases.
     * h == 0 means the points have the same X (in affine).
     * r == 0 additionally means the same Y → equal points → double.
     * r != 0 means opposite Y → additive inverse → infinity. */
    if (uint256_is_zero(&h)) {
        if (uint256_is_zero(&r_val)) {
            jp_double_internal(r, p);
        } else {
            r[0] = JP_INF_X;
            r[1] = JP_INF_Y;
            r[2] = JP_INF_Z;
        }
        return;
    }

    uint256_t h2, h3, v, x3, y3, z3;

    /* h2 = h²,  h3 = h * h2 */
    fsqr_internal(&h2, &h);
    fmul_internal(&h3, &h, &h2);

    /* v = u1 * h2 */
    fmul_internal(&v, &u1, &h2);

    /* x3 = r² - h3 - 2*v */
    uint256_t r_sq, two_v;
    fsqr_internal(&r_sq, &r_val);
    fmul_internal(&two_v, &SMALL_2, &v);
    fsub_internal(&tmp, &r_sq, &h3);
    fsub_internal(&x3, &tmp, &two_v);

    /* y3 = r * (v - x3) - s1 * h3 */
    uint256_t v_minus_x3, s1h3;
    fsub_internal(&v_minus_x3, &v, &x3);
    fmul_internal(&tmp, &r_val, &v_minus_x3);
    fmul_internal(&s1h3, &s1, &h3);
    fsub_internal(&y3, &tmp, &s1h3);

    /* z3 = h * Z1 * Z2 */
    fmul_internal(&tmp, &p[2], &q[2]);
    fmul_internal(&z3, &h, &tmp);

    r[0] = x3;
    r[1] = y3;
    r[2] = z3;
}

/*
 * jp_neg_internal — negate a Jacobian point.
 *
 * Negation simply flips the Y coordinate: (X, Y, Z) → (X, -Y, Z).
 * The point at infinity (Z = 0) is its own negation.
 *
 * fneg_internal handles the zero case branchlessly (fneg(0) = 0),
 * so this function requires no special-casing.
 *
 * Matches the Ruby jp_neg implementation exactly.
 */
void jp_neg_internal(uint256_t r[3], const uint256_t p[3])
{
    r[0] = p[0];
    fneg_internal(&r[1], &p[1]);
    r[2] = p[2];
}

/* -----------------------------------------------------------------------
 * Ruby-facing wrapper functions
 * ----------------------------------------------------------------------- */

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.jp_double(point) -> Array
 *
 * Double a Jacobian point.
 *
 * @param point [Array(Integer, Integer, Integer)] Jacobian point [X, Y, Z]
 * @return [Array(Integer, Integer, Integer)] doubled point
 */
static VALUE rb_jp_double(VALUE self, VALUE rb_point)
{
    (void)self;
    uint256_t p[3], r[3];
    unpack_point(p, rb_point);
    jp_double_internal(r, p);
    return pack_point(r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.jp_add(p, q) -> Array
 *
 * Add two Jacobian points.
 *
 * @param p [Array(Integer, Integer, Integer)] first Jacobian point [X, Y, Z]
 * @param q [Array(Integer, Integer, Integer)] second Jacobian point [X, Y, Z]
 * @return [Array(Integer, Integer, Integer)] sum
 */
static VALUE rb_jp_add(VALUE self, VALUE rb_p, VALUE rb_q)
{
    (void)self;
    uint256_t p[3], q[3], r[3];
    unpack_point(p, rb_p);
    unpack_point(q, rb_q);
    jp_add_internal(r, p, q);
    return pack_point(r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.jp_neg(point) -> Array
 *
 * Negate a Jacobian point (flip the Y coordinate).
 *
 * @param point [Array(Integer, Integer, Integer)] Jacobian point [X, Y, Z]
 * @return [Array(Integer, Integer, Integer)] negated point
 */
static VALUE rb_jp_neg(VALUE self, VALUE rb_point)
{
    (void)self;
    uint256_t p[3], r[3];
    unpack_point(p, rb_point);
    jp_neg_internal(r, p);
    return pack_point(r);
}

/* -----------------------------------------------------------------------
 * Registration — called from Init_secp256k1_native in secp256k1_native.c
 * ----------------------------------------------------------------------- */

void register_jacobian_methods(VALUE mod)
{
    rb_define_module_function(mod, "jp_double", rb_jp_double, 1);
    rb_define_module_function(mod, "jp_add",    rb_jp_add,    2);
    rb_define_module_function(mod, "jp_neg",    rb_jp_neg,    1);
}
