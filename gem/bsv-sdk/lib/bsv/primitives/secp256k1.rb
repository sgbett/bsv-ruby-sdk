# frozen_string_literal: true

require 'secp256k1'

module BSV
  module Primitives
    # Backwards-compatibility alias: BSV::Primitives::Secp256k1 → ::Secp256k1
    # This mapping will be removed in the next major version.
    Secp256k1 = ::Secp256k1
  end
end
