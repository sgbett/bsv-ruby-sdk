# frozen_string_literal: true

# NOTE: This file previously tested `Curve.ec_key_from_private_bytes`,
# `Curve.ec_key_from_public_bytes`, and the DER-parsing `BSVShimEC.new(der)`
# constructor. All three were deleted in the A4 crypto hardening pass
# (HLR #316) as dead code — no production path used them.
#
# The corresponding conformance coverage has been replaced by:
#   - spec/bsv/primitives/curve_spec.rb  (multiply_generator_ct, multiply_point_ct)
#   - spec/bsv/primitives/secp256k1_spec.rb  (mul_ct Montgomery ladder)
#
# This file is intentionally left with no examples so it continues to be
# loadable (avoiding a broken require chain) but does not produce failures.
