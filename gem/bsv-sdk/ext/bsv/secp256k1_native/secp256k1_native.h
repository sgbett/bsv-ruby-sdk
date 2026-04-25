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
 * Ruby Integer <-> uint256_t marshalling helpers
 * ----------------------------------------------------------------------- */

/* Flags for rb_integer_pack / rb_integer_unpack:
 *  - LSWORD_FIRST: first word in the array is the least-significant
 *  - NATIVE_BYTE_ORDER: use platform byte order within each word
 * Together these match the uint256_t layout (4 × uint64_t, little-endian words). */
#define U256_PACK_FLAGS (INTEGER_PACK_LSWORD_FIRST | INTEGER_PACK_NATIVE_BYTE_ORDER)

/* Convert a Ruby Integer to uint256_t.
 *
 * Raises ArgumentError if the value is negative or too large for 256 bits. */
static uint256_t rb_to_uint256(VALUE rb_int) {
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

/* Convert a uint256_t to a Ruby Integer. */
static VALUE uint256_to_rb(const uint256_t *n) {
    return rb_integer_unpack(n->d, 4, sizeof(uint64_t), 0, U256_PACK_FLAGS);
}

#endif /* SECP256K1_NATIVE_H */
