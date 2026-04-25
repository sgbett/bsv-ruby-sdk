#ifndef SECP256K1_NATIVE_H
#define SECP256K1_NATIVE_H

#include "ruby.h"
#include <stdint.h>
#include <string.h>

/* 128-bit unsigned integer — available on GCC/Clang with -std=c99 on
 * all platforms supported by this extension (Linux x86_64, macOS arm64/x86_64).
 * extconf.rb guards entry to this compilation unit on __uint128_t availability.
 * Ruby's own config.h may already define uint128_t as a macro, so guard here. */
#ifndef uint128_t
typedef unsigned __int128 uint128_t;
#endif

/* 256-bit unsigned integer stored as 4 × 64-bit limbs in little-endian order
 * (d[0] is the least-significant 64-bit word). */
typedef struct {
    uint64_t d[4];
} uint256_t;

/* -----------------------------------------------------------------------
 * secp256k1 field prime: P = 2^256 - 2^32 - 977
 * Stored little-endian: d[0] = least significant word.
 * ----------------------------------------------------------------------- */
static const uint256_t FIELD_P = {{
    0xFFFFFFFEFFFFFC2FULL,  /* bits   0-63  */
    0xFFFFFFFFFFFFFFFFULL,  /* bits  64-127 */
    0xFFFFFFFFFFFFFFFFULL,  /* bits 128-191 */
    0xFFFFFFFFFFFFFFFFULL   /* bits 192-255 */
}};

/* -----------------------------------------------------------------------
 * secp256k1 curve order: N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE
 *                             BAAEDCE6AF48A03BBFD25E8CD0364141
 * Stored little-endian.
 * ----------------------------------------------------------------------- */
static const uint256_t CURVE_N = {{
    0xBFD25E8CD0364141ULL,  /* bits   0-63  */
    0xBAAEDCE6AF48A03BULL,  /* bits  64-127 */
    0xFFFFFFFFFFFFFFFEULL,  /* bits 128-191 */
    0xFFFFFFFFFFFFFFFFULL   /* bits 192-255 */
}};

/* -----------------------------------------------------------------------
 * Low-level 256-bit helpers — defined in field.c, declared here so that
 * scalar.c and jacobian.c can call them without crossing the Ruby↔C boundary.
 * ----------------------------------------------------------------------- */

uint64_t uint256_add(uint256_t *r, const uint256_t *a, const uint256_t *b);
uint64_t uint256_sub(uint256_t *r, const uint256_t *a, const uint256_t *b);
void     uint256_copy(uint256_t *dst, const uint256_t *src);
int      uint256_bit(const uint256_t *x, int i);
uint64_t uint256_is_zero(const uint256_t *x);

/* -----------------------------------------------------------------------
 * Ruby Integer <-> uint256_t marshalling helpers
 * ----------------------------------------------------------------------- */

/* Flags for rb_integer_pack / rb_integer_unpack:
 *  - LSWORD_FIRST: first word in the array is the least-significant
 *  - NATIVE_BYTE_ORDER: use platform byte order within each word
 * Together these match the uint256_t layout (4 × uint64_t, little-endian words). */
#define U256_PACK_FLAGS (INTEGER_PACK_LSWORD_FIRST | INTEGER_PACK_NATIVE_BYTE_ORDER)

/* Convert a Ruby Integer to uint256_t.
 *
 * Raises ArgumentError if the value is negative or too large for 256 bits.
 * Declared here; defined in field.c so only one copy exists in the binary. */
uint256_t rb_to_uint256(VALUE rb_int);

/* Convert a uint256_t to a Ruby Integer.
 * Declared here; defined in field.c so only one copy exists in the binary. */
VALUE uint256_to_rb(const uint256_t *n);

/* -----------------------------------------------------------------------
 * Field arithmetic — internal functions declared here so that jacobian.c
 * can call them directly without crossing the Ruby↔C boundary.
 * ----------------------------------------------------------------------- */

void fred_internal(uint256_t *r, const uint256_t *hi, const uint256_t *lo);
void fmul_internal(uint256_t *r, const uint256_t *a, const uint256_t *b);
void fsqr_internal(uint256_t *r, const uint256_t *a);
void fadd_internal(uint256_t *r, const uint256_t *a, const uint256_t *b);
void fsub_internal(uint256_t *r, const uint256_t *a, const uint256_t *b);
void fneg_internal(uint256_t *r, const uint256_t *a);
void finv_internal(uint256_t *r, const uint256_t *a);
int  fsqrt_internal(uint256_t *r, const uint256_t *a);

/* Registration helper — called from Init_secp256k1_native. */
void register_field_methods(VALUE mod);

/* -----------------------------------------------------------------------
 * Scalar arithmetic — internal functions declared here so that jacobian.c
 * can call them directly without crossing the Ruby↔C boundary.
 * ----------------------------------------------------------------------- */

void scalar_reduce(uint256_t *r, const uint256_t *hi, const uint256_t *lo);
void scalar_mul_internal(uint256_t *r, const uint256_t *a, const uint256_t *b);
void scalar_add_internal(uint256_t *r, const uint256_t *a, const uint256_t *b);
void scalar_inv_internal(uint256_t *r, const uint256_t *a);

/* Registration helper — called from Init_secp256k1_native. */
void register_scalar_methods(VALUE mod);

/* -----------------------------------------------------------------------
 * Jacobian point operations — internal functions declared here so that
 * future modules (e.g. a scalar multiply module) can call them directly
 * in C without crossing the Ruby↔C boundary.
 * ----------------------------------------------------------------------- */

void jp_double_internal(uint256_t r[3], const uint256_t p[3]);
void jp_add_internal(uint256_t r[3], const uint256_t p[3], const uint256_t q[3]);
void jp_neg_internal(uint256_t r[3], const uint256_t p[3]);
void scalar_multiply_ct_internal(uint256_t r[3], const uint256_t *k, const uint256_t base[3]);

/* Registration helper — called from Init_secp256k1_native. */
void register_jacobian_methods(VALUE mod);

#endif /* SECP256K1_NATIVE_H */
