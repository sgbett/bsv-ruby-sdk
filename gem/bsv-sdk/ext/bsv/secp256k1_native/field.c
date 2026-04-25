/* frozen_string_literal: true */
#include "secp256k1_native.h"

/*
 * field.c — Field arithmetic modulo the secp256k1 prime P.
 *
 * P = 2^256 - 2^32 - 977  (= 2^256 - 0x1000003D1)
 *
 * All internal functions accept and return uint256_t values whose limbs
 * are in the range [0, P).  Ruby-facing wrappers handle marshalling via
 * rb_integer_pack / rb_integer_unpack.
 *
 * Constant-time discipline
 * ------------------------
 * fred, fsub, and fneg use branchless conditional selection (bitwise
 * masks derived from carry/borrow flags) so that execution time does not
 * depend on the field values.  finv and fsqrt iterate over the bits of
 * the public constants P-2 and (P+1)/4, which is safe because those
 * constants are not secret.
 */

/* -----------------------------------------------------------------------
 * Ruby Integer <-> uint256_t marshalling — defined here (not in the header)
 * so that only one copy of each function exists in the linked extension.
 * ----------------------------------------------------------------------- */

uint256_t rb_to_uint256(VALUE rb_int)
{
    uint256_t n;
    memset(&n, 0, sizeof(n));
    int result = rb_integer_pack(rb_int, n.d, 4, sizeof(uint64_t), 0, U256_PACK_FLAGS);
    if (result < 0) {
        rb_raise(rb_eArgError, "value is negative (expected non-negative integer)");
    }
    if (result > 1) {
        rb_raise(rb_eArgError, "value exceeds 256 bits");
    }
    return n;
}

VALUE uint256_to_rb(const uint256_t *n)
{
    return rb_integer_unpack(n->d, 4, sizeof(uint64_t), 0, U256_PACK_FLAGS);
}

/* -----------------------------------------------------------------------
 * Compile-time constants
 * ----------------------------------------------------------------------- */

/* Fast-reduction constant: 2^256 ≡ 0x1000003D1 (mod P).
 * This is the value c such that  x mod P = x_lo + c × x_hi  (two folds). */
#define FRED_C UINT64_C(0x1000003D1)

/* P - 2, the exponent for Fermat's little theorem (field inverse).
 * P = FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
 * P-2 = FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
 * Little-endian limb order (d[0] = least-significant). */
static const uint256_t P_MINUS_2 = {{
    0xFFFFFFFEFFFFFC2DULL,  /* bits   0-63  */
    0xFFFFFFFFFFFFFFFFULL,  /* bits  64-127 */
    0xFFFFFFFFFFFFFFFFULL,  /* bits 128-191 */
    0xFFFFFFFFFFFFFFFFULL   /* bits 192-255 */
}};

/* (P + 1) / 4, the exponent for the modular square root.
 * (P+1)/4 = 3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBFFFFF0C
 * Valid because P ≡ 3 (mod 4).
 * Little-endian limb order. */
static const uint256_t P_PLUS1_DIV4 = {{
    0xFFFFFFFFBFFFFF0CULL,  /* bits   0-63  */
    0xFFFFFFFFFFFFFFFFULL,  /* bits  64-127 */
    0xFFFFFFFFFFFFFFFFULL,  /* bits 128-191 */
    0x3FFFFFFFFFFFFFFFULL   /* bits 192-255 */
}};

/* Field element 1 */
static const uint256_t FIELD_ONE = {{ 1ULL, 0ULL, 0ULL, 0ULL }};

/* -----------------------------------------------------------------------
 * Low-level 256-bit helpers — declared in secp256k1_native.h so scalar.c
 * and jacobian.c can call them without crossing the Ruby↔C boundary.
 * ----------------------------------------------------------------------- */

/* Add two 256-bit integers; return carry (0 or 1). */
uint64_t uint256_add(uint256_t *r, const uint256_t *a, const uint256_t *b)
{
    uint128_t acc;
    uint64_t carry = 0;
    int i;
    for (i = 0; i < 4; i++) {
        acc = (uint128_t)a->d[i] + b->d[i] + carry;
        r->d[i] = (uint64_t)acc;
        carry   = (uint64_t)(acc >> 64);
    }
    return carry;
}

/* Subtract two 256-bit integers; return borrow (0 or 1).
 *
 * Uses __uint128_t so the borrow logic is unambiguous — no risk of
 * overflow in the borrow expression. */
uint64_t uint256_sub(uint256_t *r, const uint256_t *a, const uint256_t *b)
{
    uint128_t acc;
    uint64_t borrow = 0;
    int i;
    for (i = 0; i < 4; i++) {
        acc      = (uint128_t)a->d[i] - b->d[i] - borrow;
        r->d[i]  = (uint64_t)acc;
        /* Branchless borrow: extract the sign bit of the 128-bit result. */
        borrow   = (uint64_t)(acc >> 127);
    }
    return borrow;
}

/* Copy src into dst. */
void uint256_copy(uint256_t *dst, const uint256_t *src)
{
    dst->d[0] = src->d[0];
    dst->d[1] = src->d[1];
    dst->d[2] = src->d[2];
    dst->d[3] = src->d[3];
}

/* Return 1 if bit i of x is set, 0 otherwise. */
int uint256_bit(const uint256_t *x, int i)
{
    return (int)((x->d[i >> 6] >> (i & 63)) & 1);
}

/* Return 1 if x is zero, 0 otherwise — branchless.
 * Declared in secp256k1_native.h so jacobian.c and scalar.c can call it. */
uint64_t uint256_is_zero(const uint256_t *x)
{
    uint64_t v = x->d[0] | x->d[1] | x->d[2] | x->d[3];
    /* If v == 0, ~v + 1 = 0 (overflow wraps); this is non-zero iff v != 0.
     * Simpler: set bit 63 and shift; or just use carry arithmetic. */
    v = v | (v >> 32); /* fold high into low */
    v = v | (v >> 16);
    v = v | (v >> 8);
    v = v | (v >> 4);
    v = v | (v >> 2);
    v = v | (v >> 1);
    return (v & 1) ^ 1; /* 1 if all bits were 0, 0 otherwise */
}

/* -----------------------------------------------------------------------
 * Internal field operations — visible to jacobian.c via the header
 * ----------------------------------------------------------------------- */

/*
 * fred_internal — fast reduction modulo P.
 *
 * Accepts a 512-bit value split into hi[4] (high 256 bits) and lo[4]
 * (low 256 bits) and reduces to a 256-bit result in [0, P).
 *
 * Exploits P = 2^256 - c where c = 0x1000003D1:
 *   x mod P  =  x_lo + c × x_hi   (first fold)
 * The first fold can produce at most ~288 bits; one more fold suffices:
 *   result   =  first_lo + c × first_hi
 * After two folds the value fits in 256 bits plus a tiny overflow that
 * a single conditional subtraction of P handles.
 *
 * The final subtraction is branchless: compute r - P; if the result
 * underflows (borrow), keep r; otherwise keep r - P.
 */
void fred_internal(uint256_t *r, const uint256_t *hi, const uint256_t *lo)
{
    /* First fold: tmp = lo + c × hi
     *
     * c × hi can be split: c = 2^32 + 977
     * c × hi = hi << 32 + 977 × hi
     *
     * We accumulate into 5 limbs (extra carry limb at index 4) to avoid
     * losing bits, then do a second fold on whatever sits above bit 255. */

    uint128_t acc;
    uint64_t carry;
    int i;

    /* tmp: 5 limbs to capture overflow from the first fold */
    uint64_t tmp[5];

    /* Compute c × hi with carry.  c fits in 33 bits, hi fits in 64 bits
     * each, so each product fits in 97 bits — safe in uint128_t. */
    acc   = 0;
    carry = 0;
    for (i = 0; i < 4; i++) {
        acc       = (uint128_t)hi->d[i] * FRED_C + lo->d[i] + carry;
        tmp[i]    = (uint64_t)acc;
        carry     = (uint64_t)(acc >> 64);
    }
    tmp[4] = carry;

    /* Second fold: overflow = tmp[4].
     *
     * After the first fold, tmp[4] can be as large as ~0x1000003D0 (about
     * 33 bits), because hi < P < 2^256 and c = 0x1000003D1, so the carry
     * out of the first fold is at most (P-1)*c / 2^256 < c.
     *
     * We need to add overflow × c back into tmp[0..3].  overflow × c may
     * be as large as ~0x1000003D1 * 0x1000003D1 ≈ 2^66, so it spans two
     * 64-bit limbs.  Use uint128_t to handle the full product correctly. */
    uint64_t overflow = tmp[4];
    uint128_t fold = (uint128_t)overflow * FRED_C;
    acc   = (uint128_t)tmp[0] + (uint64_t)fold;
    r->d[0] = (uint64_t)acc;
    carry   = (uint64_t)(acc >> 64) + (uint64_t)(fold >> 64);

    for (i = 1; i < 4; i++) {
        acc       = (uint128_t)tmp[i] + carry;
        r->d[i]   = (uint64_t)acc;
        carry     = (uint64_t)(acc >> 64);
    }
    /* After two complete folds the result fits in 256 bits (carry is 0). */

    /* Branchless final conditional subtraction.
     *
     * Compute reduced = r - P.  If it underflows (borrow == 1), r < P so keep r.
     * If borrow == 0, r >= P so keep reduced. */
    uint256_t reduced;
    uint64_t borrow = uint256_sub(&reduced, r, &FIELD_P);

    /* mask = all 1s if borrow == 1 (keep r), all 0s if borrow == 0 (keep reduced). */
    uint64_t mask = -(uint64_t)(borrow != 0);
    for (i = 0; i < 4; i++) {
        r->d[i] = (r->d[i] & mask) | (reduced.d[i] & ~mask);
    }
}

/*
 * fmul_internal — 256×256 → 512-bit product, then fred_internal.
 *
 * Uses 4×4 schoolbook multiplication with uint128_t accumulators.
 * The 8-limb product is split into hi[4] and lo[4] for fred_internal.
 */
void fmul_internal(uint256_t *r, const uint256_t *a, const uint256_t *b)
{
    /* 8-limb product accumulator */
    uint64_t product[8];
    uint128_t acc;
    uint64_t carry;
    int i, j;

    for (i = 0; i < 8; i++) product[i] = 0;

    for (i = 0; i < 4; i++) {
        carry = 0;
        for (j = 0; j < 4; j++) {
            acc = (uint128_t)a->d[i] * b->d[j] + product[i + j] + carry;
            product[i + j] = (uint64_t)acc;
            carry          = (uint64_t)(acc >> 64);
        }
        acc = (uint128_t)product[i + 4] + carry;
        product[i + 4] = (uint64_t)acc;
        if (i < 3) product[i + 5] += (uint64_t)(acc >> 64);
    }

    uint256_t lo, hi;
    lo.d[0] = product[0]; lo.d[1] = product[1];
    lo.d[2] = product[2]; lo.d[3] = product[3];
    hi.d[0] = product[4]; hi.d[1] = product[5];
    hi.d[2] = product[6]; hi.d[3] = product[7];

    fred_internal(r, &hi, &lo);
}

/*
 * fsqr_internal — optimised squaring using the identity that cross-terms
 * appear twice.
 *
 * For a = (a0, a1, a2, a3), a² has:
 *   - Diagonal terms: ai²  (4 terms)
 *   - Cross terms: 2 × ai × aj for i < j  (6 terms)
 * This saves 6 multiplications vs generic fmul.
 */
void fsqr_internal(uint256_t *r, const uint256_t *a)
{
    /* Use the same schoolbook approach as fmul_internal but with b == a.
     *
     * The optimised squaring identity (cross-terms × 2) is mathematically
     * correct but requires care when the double-width product overflows
     * uint128_t.  For simplicity and correctness we delegate to fmul_internal
     * directly; the compiler typically optimises a² to use the same codepath.
     * A hand-tuned squaring optimisation can be added later as a separate task. */
    fmul_internal(r, a, a);
}

/*
 * fadd_internal — modular addition.
 *
 * Computes a + b, then branchlessly subtracts P if the result >= P.
 */
void fadd_internal(uint256_t *r, const uint256_t *a, const uint256_t *b)
{
    uint256_t sum;
    uint64_t overflow = uint256_add(&sum, a, b);

    /* If overflow or sum >= P, subtract P. */
    uint256_t reduced;
    uint64_t borrow = uint256_sub(&reduced, &sum, &FIELD_P);

    /* Keep reduced unless (no overflow AND borrow).
     * If overflow == 1 : sum > 2^256 > P, so we definitely want reduced.
     * If overflow == 0 and borrow == 0 : sum >= P, want reduced.
     * If overflow == 0 and borrow == 1 : sum < P, want sum.
     * Combined: keep sum iff (overflow == 0 && borrow == 1). */
    uint64_t keep_original = (~overflow) & borrow;
    uint64_t mask = -(uint64_t)(keep_original != 0); /* all 1s iff sum < P */
    int i;
    for (i = 0; i < 4; i++) {
        r->d[i] = (sum.d[i] & mask) | (reduced.d[i] & ~mask);
    }
}

/*
 * fsub_internal — modular subtraction.
 *
 * Computes a - b; if the result underflows, adds P back — branchlessly.
 */
void fsub_internal(uint256_t *r, const uint256_t *a, const uint256_t *b)
{
    uint256_t diff;
    uint64_t borrow = uint256_sub(&diff, a, b);

    /* If borrow == 1 then a < b and we need to add P. */
    uint256_t corrected;
    uint64_t carry = uint256_add(&corrected, &diff, &FIELD_P);
    (void)carry; /* carry is 0 here since diff + P < 2^256 when borrow == 1 */

    /* mask: all 1s if borrow == 1 (use corrected), all 0s otherwise (use diff). */
    uint64_t mask = -(uint64_t)(borrow != 0);
    int i;
    for (i = 0; i < 4; i++) {
        r->d[i] = (corrected.d[i] & mask) | (diff.d[i] & ~mask);
    }
}

/*
 * fneg_internal — modular negation.
 *
 * Returns P - a for non-zero a, and 0 for a == 0 — branchlessly.
 */
void fneg_internal(uint256_t *r, const uint256_t *a)
{
    uint256_t negated;
    uint256_sub(&negated, &FIELD_P, a); /* P - a; no borrow since a <= P-1 */

    /* If a == 0 the result should be 0, not P. */
    uint64_t is_zero = uint256_is_zero(a);
    uint64_t mask = -(uint64_t)(is_zero != 0); /* all 1s if a is zero */
    int i;
    for (i = 0; i < 4; i++) {
        /* zero mask: 0 where is_zero, negated.d[i] where not */
        r->d[i] = negated.d[i] & ~mask;
    }
}

/*
 * finv_internal — modular inverse via Fermat's little theorem.
 *
 * Computes a^(P-2) mod P using square-and-multiply over the 256 bits of P-2.
 * The exponent P-2 is a public constant so branching on its bits is safe.
 */
void finv_internal(uint256_t *r, const uint256_t *a)
{
    uint256_t result;
    uint256_t base;
    uint256_copy(&result, &FIELD_ONE);
    uint256_copy(&base, a);

    /* Process bits from MSB (255) to LSB (0). */
    int i;
    for (i = 255; i >= 0; i--) {
        fsqr_internal(&result, &result);
        if (uint256_bit(&P_MINUS_2, i)) {
            fmul_internal(&result, &result, &base);
        }
    }
    uint256_copy(r, &result);
}

/*
 * fsqrt_internal — modular square root via a^((P+1)/4) mod P.
 *
 * Valid because P ≡ 3 (mod 4).  Returns 1 if a is a quadratic residue,
 * 0 otherwise.  The result is written to *r in both cases; the caller
 * should check the return value and discard *r if it returns 0.
 */
int fsqrt_internal(uint256_t *r, const uint256_t *a)
{
    uint256_t result;
    uint256_t base;
    uint256_copy(&result, &FIELD_ONE);
    uint256_copy(&base, a);

    /* Compute a^((P+1)/4) */
    int i;
    for (i = 255; i >= 0; i--) {
        fsqr_internal(&result, &result);
        if (uint256_bit(&P_PLUS1_DIV4, i)) {
            fmul_internal(&result, &result, &base);
        }
    }

    /* Verify: r² must equal a mod P */
    uint256_t check;
    fsqr_internal(&check, &result);

    /* Reduce a mod P to compare */
    uint256_t a_reduced;
    uint256_t zero = {{ 0ULL, 0ULL, 0ULL, 0ULL }};
    fred_internal(&a_reduced, &zero, a);

    /* Compare limb by limb */
    uint64_t diff = 0;
    for (i = 0; i < 4; i++) {
        diff |= (check.d[i] ^ a_reduced.d[i]);
    }

    if (diff != 0) return 0; /* not a quadratic residue */

    uint256_copy(r, &result);
    return 1;
}

/* -----------------------------------------------------------------------
 * Ruby-facing wrapper functions
 * ----------------------------------------------------------------------- */

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.fred(x) -> Integer
 *
 * Fast reduction: returns +x+ mod P.
 * Accepts a value up to 512 bits wide (stored in a Ruby Integer).
 */
static VALUE rb_fred(VALUE self, VALUE x)
{
    (void)self;
    /* fred is used for reducing wide intermediates.  Pack into 8 limbs. */
    uint64_t limbs[8];
    memset(limbs, 0, sizeof(limbs));
    int result = rb_integer_pack(x, limbs, 8, sizeof(uint64_t), 0, U256_PACK_FLAGS);
    if (result < 0) {
        rb_raise(rb_eArgError, "value is negative");
    }
    if (result > 1) {
        rb_raise(rb_eArgError, "value exceeds 512 bits");
    }

    uint256_t lo, hi;
    lo.d[0] = limbs[0]; lo.d[1] = limbs[1];
    lo.d[2] = limbs[2]; lo.d[3] = limbs[3];
    hi.d[0] = limbs[4]; hi.d[1] = limbs[5];
    hi.d[2] = limbs[6]; hi.d[3] = limbs[7];

    uint256_t r;
    fred_internal(&r, &hi, &lo);
    return uint256_to_rb(&r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.fmul(a, b) -> Integer
 *
 * Modular multiplication: returns +(a * b) mod P+.
 */
static VALUE rb_fmul(VALUE self, VALUE a, VALUE b)
{
    (void)self;
    uint256_t ua = rb_to_uint256(a);
    uint256_t ub = rb_to_uint256(b);
    uint256_t r;
    fmul_internal(&r, &ua, &ub);
    return uint256_to_rb(&r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.fsqr(a) -> Integer
 *
 * Modular squaring: returns +(a * a) mod P+.
 */
static VALUE rb_fsqr(VALUE self, VALUE a)
{
    (void)self;
    uint256_t ua = rb_to_uint256(a);
    uint256_t r;
    fsqr_internal(&r, &ua);
    return uint256_to_rb(&r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.fadd(a, b) -> Integer
 *
 * Modular addition: returns +(a + b) mod P+.
 */
static VALUE rb_fadd(VALUE self, VALUE a, VALUE b)
{
    (void)self;
    uint256_t ua = rb_to_uint256(a);
    uint256_t ub = rb_to_uint256(b);
    uint256_t r;
    fadd_internal(&r, &ua, &ub);
    return uint256_to_rb(&r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.fsub(a, b) -> Integer
 *
 * Modular subtraction: returns +(a - b) mod P+.
 */
static VALUE rb_fsub(VALUE self, VALUE a, VALUE b)
{
    (void)self;
    uint256_t ua = rb_to_uint256(a);
    uint256_t ub = rb_to_uint256(b);
    uint256_t r;
    fsub_internal(&r, &ua, &ub);
    return uint256_to_rb(&r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.fneg(a) -> Integer
 *
 * Modular negation: returns +(-a) mod P+ (i.e. +P - a+ for non-zero a).
 */
static VALUE rb_fneg(VALUE self, VALUE a)
{
    (void)self;
    uint256_t ua = rb_to_uint256(a);
    uint256_t r;
    fneg_internal(&r, &ua);
    return uint256_to_rb(&r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.finv(a) -> Integer
 *
 * Modular inverse: returns +a^(P-2) mod P+.
 *
 * @raise [ArgumentError] if a is zero.
 */
static VALUE rb_finv(VALUE self, VALUE a)
{
    (void)self;
    uint256_t ua = rb_to_uint256(a);

    /* Reduce a mod P before zero-checking */
    uint256_t zero_limbs = {{ 0ULL, 0ULL, 0ULL, 0ULL }};
    uint256_t a_reduced;
    fred_internal(&a_reduced, &zero_limbs, &ua);

    if (uint256_is_zero(&a_reduced)) {
        rb_raise(rb_eArgError, "field inverse is undefined for zero");
    }

    uint256_t r;
    finv_internal(&r, &a_reduced);
    return uint256_to_rb(&r);
}

/*
 * call-seq:
 *   BSV::Primitives::Secp256k1Native.fsqrt(a) -> Integer or nil
 *
 * Modular square root: returns +a^((P+1)/4) mod P+, or +nil+ if +a+ is
 * not a quadratic residue modulo P.
 */
static VALUE rb_fsqrt(VALUE self, VALUE a)
{
    (void)self;
    uint256_t ua = rb_to_uint256(a);

    /* Reduce a mod P first */
    uint256_t zero_limbs = {{ 0ULL, 0ULL, 0ULL, 0ULL }};
    uint256_t a_reduced;
    fred_internal(&a_reduced, &zero_limbs, &ua);

    uint256_t r;
    int ok = fsqrt_internal(&r, &a_reduced);
    if (!ok) return Qnil;
    return uint256_to_rb(&r);
}

/* -----------------------------------------------------------------------
 * Registration — called from Init_secp256k1_native in secp256k1_native.c
 * ----------------------------------------------------------------------- */

void register_field_methods(VALUE mod)
{
    rb_define_module_function(mod, "fred",  rb_fred,  1);
    rb_define_module_function(mod, "fmul",  rb_fmul,  2);
    rb_define_module_function(mod, "fsqr",  rb_fsqr,  1);
    rb_define_module_function(mod, "fadd",  rb_fadd,  2);
    rb_define_module_function(mod, "fsub",  rb_fsub,  2);
    rb_define_module_function(mod, "fneg",  rb_fneg,  1);
    rb_define_module_function(mod, "finv",  rb_finv,  1);
    rb_define_module_function(mod, "fsqrt", rb_fsqrt, 1);
}
