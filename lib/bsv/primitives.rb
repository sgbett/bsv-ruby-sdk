# frozen_string_literal: true

module BSV
  # Cryptographic primitives for the BSV blockchain.
  #
  # Provides keys, curves, hashing, digital signatures, encryption,
  # HD key derivation (BIP-32), and mnemonic phrase generation (BIP-39).
  # All cryptography uses Ruby's stdlib +openssl+ — no external gems.
  module Primitives
    autoload :Curve,        'bsv/primitives/curve'
    autoload :Digest,       'bsv/primitives/digest'
    autoload :Base58,       'bsv/primitives/base58'
    autoload :Signature,    'bsv/primitives/signature'
    autoload :ECDSA,        'bsv/primitives/ecdsa'
    autoload :ECIES,        'bsv/primitives/ecies'
    autoload :BSM,          'bsv/primitives/bsm'
    autoload :Schnorr,      'bsv/primitives/schnorr'
    autoload :PublicKey,    'bsv/primitives/public_key'
    autoload :PrivateKey,   'bsv/primitives/private_key'
    autoload :ExtendedKey,  'bsv/primitives/extended_key'
    autoload :Mnemonic,     'bsv/primitives/mnemonic'
    autoload :SymmetricKey, 'bsv/primitives/symmetric_key'
  end
end
