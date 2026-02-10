# frozen_string_literal: true

module BSV
  module Primitives
    autoload :Curve,      'bsv/primitives/curve'
    autoload :Digest,     'bsv/primitives/digest'
    autoload :Base58,     'bsv/primitives/base58'
    autoload :Signature,  'bsv/primitives/signature'
    autoload :ECDSA,      'bsv/primitives/ecdsa'
    autoload :ECIES,      'bsv/primitives/ecies'
    autoload :BSM,        'bsv/primitives/bsm'
    autoload :PublicKey,  'bsv/primitives/public_key'
    autoload :PrivateKey,  'bsv/primitives/private_key'
    autoload :ExtendedKey, 'bsv/primitives/extended_key'
    autoload :Mnemonic,    'bsv/primitives/mnemonic'
  end
end
