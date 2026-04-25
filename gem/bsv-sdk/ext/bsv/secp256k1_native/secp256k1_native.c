#include "secp256k1_native.h"

/*
 * BSV::Primitives::Secp256k1Native
 *
 * Native C extension providing accelerated secp256k1 field, scalar, and point
 * arithmetic. Methods are registered here as tasks are implemented; the module
 * is intentionally empty at scaffold stage.
 *
 * The extension slots in *below* BSV::Primitives::Secp256k1 — it does not
 * replace the OpenSSL shim or the public Point API. secp256k1.rb delegates
 * hot-path operations to this module when available.
 */

/* Module handle — set during Init, used by sub-files when they register methods. */
VALUE rb_mBSV;
VALUE rb_mBSVPrimitives;
VALUE rb_mSecp256k1Native;

/*
 * Entry point called by Ruby when the extension is required.
 *
 * Defines BSV::Primitives::Secp256k1Native as an empty module. Field,
 * scalar, and point methods are added in subsequent tasks.
 */
void Init_secp256k1_native(void) {
    rb_mBSV            = rb_define_module("BSV");
    rb_mBSVPrimitives  = rb_define_module_under(rb_mBSV, "Primitives");
    rb_mSecp256k1Native = rb_define_module_under(rb_mBSVPrimitives, "Secp256k1Native");
}
