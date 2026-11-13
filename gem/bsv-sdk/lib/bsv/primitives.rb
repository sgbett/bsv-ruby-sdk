# frozen_string_literal: true

module BSV
  # Cryptographic primitives for the BSV blockchain.
  #
  # Provides keys, curves, hashing, digital signatures, encryption,
  # HD key derivation (BIP-32), and mnemonic phrase generation (BIP-39).
  # All cryptography uses Ruby's stdlib +openssl+ — no external gems.
  module Primitives
    autoload :FieldMath,    'bsv/primitives/field_math'
    autoload :Hex,          'bsv/primitives/hex'
    autoload :Ripemd160,    'bsv/primitives/ripemd160'
    autoload :Secp256k1,    'bsv/primitives/secp256k1'
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
    autoload :SymmetricKey,         'bsv/primitives/symmetric_key'
    autoload :SignedMessage,        'bsv/primitives/signed_message'
    autoload :EncryptedMessage,     'bsv/primitives/encrypted_message'
    autoload :PointInFiniteField,   'bsv/primitives/point_in_finite_field'
    autoload :Polynomial,           'bsv/primitives/polynomial'
    autoload :KeyShares,            'bsv/primitives/key_shares'
  end
end
