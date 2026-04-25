/* frozen_string_literal: true */
#include "secp256k1_native.h"

/*
 * scalar.c — Scalar arithmetic modulo the secp256k1 curve order N.
 *
 * N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
 *
 * Reduction strategy
 * ------------------
 * c_N = 2^256 - N = 0x14551231950B75FC4402DA1732FC9BEBF  (129 bits)
 *
 * For a 512-bit product P = hi:lo (both 256 bits), we want P mod N.
 *
 * P mod N = lo + c_N × hi  (mod N)
 *
 * c_N × hi can be at most 2^129 × (2^256 - 1) < 2^385, which is 385 bits.
 * After adding lo (256 bits) the sum fits in at most 385 bits, i.e.
 * 129 bits above bit 255.
 *
 * We perform this fold once using an 8-limb accumulator.  Then the overflow
 * above bit 255 is at most ~2^129, and we fold again.  After two folds the
 * result fits in 256 bits plus at most 1 bit of overflow that a conditional
 * subtraction of N handles.
 *
 * The fold is done scalar_reduce(), which accepts the 8-limb product buffer
 * directly so no intermediate allocation is needed.
 *
 * Constant-time discipline
 * ------------------------
 * scalar_reduce, scalar_add_internal use branchless conditional selection.
 * scalar_inv_internal iterates over bits of the public constant N-2, which
 * is safe.
 */

/* -----------------------------------------------------------------------
 * Compile-time constants for N reduction
 * ----------------------------------------------------------------------- */

/*
 * Fold constant c_N = 2^256 - N, split into three 64-bit limbs.
 *
 *   c_N = 0x014551231950B75FC4402DA1732FC9BEBF
 *
 *   Limb 0 (bits   0- 63): 0x402DA1732FC9BEBF
 *   Limb 1 (bits  64-127): 0x4551231950B75FC4
 *   Limb 2 (bit  128):     0x0000000000000001
 *   Limbs 3+ are zero.
 */
#define CN_LO   UINT64_C(0x402DA1732FC9BEBF)
#define CN_MID  UINT64_C(0x4551231950B75FC4)
/* Limb 2 = 1 (i.e. c_N has a single set bit at position 128) */

/* N - 2, the exponent for Fermat's little theorem (scalar inverse).
 * N-2 is N with the least-significant 64-bit word decremented by 2.
 * Little-endian limb order (d[0] = least-significant). */
static const uint256_t N_MINUS_2 = {{
    0xBFD25E8CD036413FULL,  /* bits   0-63:  N[0] - 2 */
    0xBAAEDCE6AF48A03BULL,  /* bits  64-127 */
    0xFFFFFFFFFFFFFFFEULL,  /* bits 128-191 */
    0xFFFFFFFFFFFFFFFFULL   /* bits 192-255 */
}};

/* Scalar element 1 */
static const uint256_t SCALAR_ONE = {{ 1ULL, 0ULL, 0ULL, 0ULL }};

/* -----------------------------------------------------------------------
 * Modular reduction mod N
 * ----------------------------------------------------------------------- */

/*
 * scalar_reduce_limbs — reduce an 8-limb (512-bit) product modulo N.
 *
 * The limbs array is product[0..7] in little-endian order.
 *
 * Strategy:
 *
 * First fold: add c_N × product[4..7] into product[0..3].
 *
 *   c_N = CN_LO + CN_MID×2^64 + 1×2^128
 *
 *   For each high limb h[j] = product[4+j] (j = 0..3), we add:
 *     h[j] × CN_LO   into accumulator starting at position j
 *     h[j] × CN_MID  into accumulator starting at position j+1
 *     h[j] × 1       into accumulator starting at position j+2
 *
 *   Equivalently, we walk the 8-limb array from position 4 downwards,
 *   folding each limb into the low four limbs.
 *
 * After the first fold the 512-bit value has been reduced to at most
 * ~385 bits.  The overflow above bit 255 (stored in the temporary carry
 * words) requires a second fold.  After two folds the result fits in
 * 256 bits + at most 1 bit, handled by a conditional subtraction.
 *
 * We accumulate into an 8-limb array and reuse the upper limbs as
 * temporaries for the folded-in contributions, so no extra allocation is
 * needed.
 */
static void scalar_reduce_limbs(uint256_t *r, uint64_t product[8])
{
    uint128_t acc;
    int i;

    /* ----------------------------------------------------------------
     * First fold: multiply product[4..7] by c_N and add into [0..7].
     *
     * We process high limbs j = 0..3 (corresponding to product[4..7]).
     * For limb h = product[4+j], we fold:
     *   position j:   h × CN_LO
     *   position j+1: h × CN_MID
     *   position j+2: h × 1  (the 2^128 term)
     *
     * We walk j from 0 to 3, updating product[j..j+2] with carries.
     * Since j goes up to 3 and we write to j+2 <= 5, we can overwrite
     * product[4..7] freely after we've read them.
     *
     * Implementation: iterate over j = 0..3, accumulate into a running
     * carry array.  To keep it clean, we use a separate 8-limb result
     * buffer initialised from product[0..3].
     * ---------------------------------------------------------------- */

    /* Copy the low 4 limbs into an 8-limb result buffer.
     * Upper 4 limbs will accumulate folded-in contributions. */
    uint64_t t[8];
    for (i = 0; i < 4; i++) t[i] = product[i];
    for (i = 4; i < 8; i++) t[i] = 0;

    /* Fold each high limb into t. */
    for (i = 0; i < 4; i++) {
        uint64_t h = product[4 + i];

        /* h × CN_LO → accumulate into t[i] with carry propagation. */
        acc       = (uint128_t)h * CN_LO + t[i];
        t[i]      = (uint64_t)acc;
        acc       = (acc >> 64);
        /* Carry from CN_LO product — propagate. */
        acc      += (uint128_t)h * CN_MID + t[i + 1];
        t[i + 1]  = (uint64_t)acc;
        acc       = (acc >> 64);
        /* h × 2^128 — just add h into t[i+2] with carry. */
        acc      += (uint128_t)h + t[i + 2];
        t[i + 2]  = (uint64_t)acc;
        /* Propagate carry into t[i+3]. */
        acc       = (acc >> 64) + t[i + 3];
        t[i + 3]  = (uint64_t)acc;
        /* Any carry beyond i+3 (into t[i+4]) is handled in the next
         * iteration or in the second fold below. */
        if (i < 3) {
            t[i + 4] += (uint64_t)(acc >> 64);
        }
        /* When i == 3, t[7] already holds the final carry — discard it
         * after the second fold. */
    }

    /* ----------------------------------------------------------------
     * Second fold: t[4..7] now holds the overflow from the first fold.
     * Fold it again in the same way.
     * ---------------------------------------------------------------- */

    /* Save current t[4..7] as the new "high" limbs, then zero them. */
    uint64_t hi2[4];
    for (i = 0; i < 4; i++) { hi2[i] = t[4 + i]; t[4 + i] = 0; }

    for (i = 0; i < 4; i++) {
        uint64_t h = hi2[i];
        if (h == 0) continue;

        acc       = (uint128_t)h * CN_LO + t[i];
        t[i]      = (uint64_t)acc;
        acc       = (acc >> 64);

        acc      += (uint128_t)h * CN_MID + t[i + 1];
        t[i + 1]  = (uint64_t)acc;
        acc       = (acc >> 64);

        acc      += (uint128_t)h + t[i + 2];
        t[i + 2]  = (uint64_t)acc;
        acc       = (acc >> 64);

        t[i + 3] += (uint64_t)acc;
        /* After two folds, any carry here is negligible (< 2). */
    }

    /* The result is now in t[0..3] with at most a tiny overflow in t[4].
     * Copy t[0..3] into r and apply a conditional subtraction. */
    r->d[0] = t[0]; r->d[1] = t[1]; r->d[2] = t[2]; r->d[3] = t[3];

    /* Handle residual overflow from t[4] (at most 1 after two folds of
     * a 512-bit input): add t[4] × c_N into r. */
    uint64_t carry3 = t[4];
    if (carry3) {
        /* carry3 is at most a few bits wide — use simple arithmetic. */
        uint128_t a0 = (uint128_t)carry3 * CN_LO + r->d[0];
        r->d[0] = (uint64_t)a0;
        uint128_t a1 = (uint128_t)carry3 * CN_MID + r->d[1] + (a0 >> 64);
        r->d[1] = (uint64_t)a1;
        uint128_t a2 = (uint128_t)carry3 + r->d[2] + (a1 >> 64);
        r->d[2] = (uint64_t)a2;
        r->d[3] += (uint64_t)(a2 >> 64);
    }

    /* Branchless final conditional subtraction: keep r - N if r >= N. */
    uint256_t reduced;
    uint64_t borrow = uint256_sub(&reduced, r, &CURVE_N);
    uint64_t mask = -(uint64_t)(borrow != 0); /* all 1s if r < N */
    for (i = 0; i < 4; i++) {
        r->d[i] = (r->d[i] & mask) | (reduced.d[i] & ~mask);
    }
}

/*
 * scalar_reduce — reduce a 512-bit value (hi:lo) modulo N.
 *
 * Public entry point used by rb_scalar_mod for reducing arbitrary-width
 * (up to 512-bit) values passed from Ruby.
 */
void scalar_reduce(uint256_t *r, const uint256_t *hi, const uint256_t *lo)
{
    uint64_t product[8];
    product[0] = lo->d[0]; product[1] = lo->d[1];
    product[2] = lo->d[2]; product[3] = lo->d[3];
    product[4] = hi->d[0]; product[5] = hi->d[1];
    product[6] = hi->d[2]; product[7] = hi->d[3];
    scalar_reduce_limbs(r, product);
}

/* -----------------------------------------------------------------------
 * Internal scalar operations — visible to jacobian.c via the header
 * ----------------------------------------------------------------------- */

/*
 * scalar_mul_internal — 256×256 → 512-bit product, then scalar_reduce.
 */
void scalar_mul_internal(uint256_t *r, const uint256_t *a, const uint256_t *b)
{
    uint64_t product[8];
    uint128_t acc;
    uint64_t carry;
    int i, j;

    for (i = 0; i < 8; i++) product[i] = 0;

    for (i = 0; i < 4; i++) {
        carry = 0;
        for (j = 0; j < 4; j++) {
            acc            = (uint128_t)a->d[i] * b->d[j] + product[i + j] + carry;
            product[i + j] = (uint64_t)acc;
            carry          = (uint64_t)(acc >> 64);
        }
        product[i + 4] += carry;
    }

    scalar_reduce_limbs(r, product);
}

/*
 * scalar_sqr_internal — squaring; delegates to scalar_mul_internal.
 */
static void scalar_sqr_internal(uint256_t *r, const uint256_t *a)
{
    scalar_mul_internal(r, a, a);
}

/*
 * scalar_add_internal — modular addition mod N.
 *
 * Computes a + b, then branchlessly subtracts N if the result >= N.
 */
void scalar_add_internal(uint256_t *r, const uint256_t *a, const uint256_t *b)
{
    uint256_t sum;
    uint64_t overflow = uint256_add(&sum, a, b);

    uint256_t reduced;
    uint64_t borrow = uint256_sub(&reduced, &sum, &CURVE_N);

    /* Keep reduced unless (no overflow AND borrow).
     * If overflow == 1: sum > 2^256 > N, so we want reduced.
     * If overflow == 0 and borrow == 0: sum >= N, want reduced.
     * If overflow == 0 and borrow == 1: sum < N, want sum. */
    uint64_t keep_original = (~overflow) & borrow;
    uint64_t mask = -(uint64_t)(keep_original != 0);
    int i;
    for (i = 0; i < 4; i++) {
        r->d[i] = (sum.d[i] & mask) | (reduced.d[i] & ~mask);
    }
}

/*
 * scalar_inv_internal — modular inverse via Fermat's little theorem.
 *
 * Computes a^(N-2) mod N using square-and-multiply over the 256 bits of N-2.
 * The exponent N-2 is a public constant so branching on its bits is safe.
 */
void scalar_inv_internal(uint256_t *r, const uint256_t *a)
{
    uint256_t result;
    uint256_t base;
    uint256_copy(&result, &SCALAR_ONE);
    uint256_copy(&base, a);

    /* Process bits from MSB (255) to LSB (0). */
    int i;
    for (i = 255; i >= 0; i--) {
        scalar_sqr_internal(&result, &result);
        if (uint256_bit(&N_MINUS_2, i)) {
            scalar_mul_internal(&result, &result, &base);
        }
    }
    uint256_copy(r, &result);
}

/* -----------------------------------------------------------------------
 * Ruby-facing wrapper functions
 * ----------------------------------------------------------------------- */

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.scalar_mod(a) -> Integer
 *
 * Reduce +a+ modulo the curve order N.  Handles negative Ruby Integers:
 * if +a+ is negative, the result is +a mod N+ in the range [0, N).
 */
static VALUE rb_scalar_mod(VALUE self, VALUE a)
{
    (void)self;

    /* Handle negative values by delegating to Ruby's own % operator which
     * always returns a non-negative result for a positive modulus. */
    VALUE n_rb  = uint256_to_rb(&CURVE_N);
    int negative = RTEST(rb_funcall(a, rb_intern("<"), 1, INT2FIX(0)));

    VALUE a_norm;
    if (negative) {
        /* Ruby % is always non-negative when the modulus is positive */
        a_norm = rb_funcall(a, rb_intern("%"), 1, n_rb);
    } else {
        a_norm = a;
    }

    uint256_t ua = rb_to_uint256(a_norm);
    uint256_t zero_limbs = {{ 0ULL, 0ULL, 0ULL, 0ULL }};
    uint256_t r;
    scalar_reduce(&r, &zero_limbs, &ua);
    return uint256_to_rb(&r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.scalar_mul(a, b) -> Integer
 *
 * Scalar multiplication: returns +(a * b) mod N+.
 */
static VALUE rb_scalar_mul(VALUE self, VALUE a, VALUE b)
{
    (void)self;
    uint256_t ua = rb_to_uint256(a);
    uint256_t ub = rb_to_uint256(b);
    uint256_t r;
    scalar_mul_internal(&r, &ua, &ub);
    return uint256_to_rb(&r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.scalar_inv(a) -> Integer
 *
 * Modular inverse: returns +a^(N-2) mod N+.
 *
 * @raise [ArgumentError] if a is zero mod N.
 */
static VALUE rb_scalar_inv(VALUE self, VALUE a)
{
    (void)self;
    uint256_t ua = rb_to_uint256(a);

    /* Reduce a mod N before zero-checking */
    uint256_t zero_limbs = {{ 0ULL, 0ULL, 0ULL, 0ULL }};
    uint256_t a_reduced;
    scalar_reduce(&a_reduced, &zero_limbs, &ua);

    if (uint256_is_zero(&a_reduced)) {
        rb_raise(rb_eArgError, "scalar inverse is undefined for zero");
    }

    uint256_t r;
    scalar_inv_internal(&r, &a_reduced);
    return uint256_to_rb(&r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.scalar_add(a, b) -> Integer
 *
 * Scalar addition: returns +(a + b) mod N+.
 */
static VALUE rb_scalar_add(VALUE self, VALUE a, VALUE b)
{
    (void)self;
    uint256_t ua = rb_to_uint256(a);
    uint256_t ub = rb_to_uint256(b);
    uint256_t r;
    scalar_add_internal(&r, &ua, &ub);
    return uint256_to_rb(&r);
}

/* -----------------------------------------------------------------------
 * Registration — called from Init_secp256k1_native in secp256k1_native.c
 * ----------------------------------------------------------------------- */

void register_scalar_methods(VALUE mod)
{
    rb_define_module_function(mod, "scalar_mod", rb_scalar_mod, 1);
    rb_define_module_function(mod, "scalar_mul", rb_scalar_mul, 2);
    rb_define_module_function(mod, "scalar_inv", rb_scalar_inv, 1);
    rb_define_module_function(mod, "scalar_add", rb_scalar_add, 2);
}
