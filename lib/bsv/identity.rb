# frozen_string_literal: true

module BSV
  # Identity module for BSV blockchain.
  #
  # Provides data structures and constants for resolving and displaying
  # identity information associated with BSV public keys, backed by
  # verifiable certificates managed through the BSV overlay network.
  module Identity
    autoload :DisplayableIdentity,  'bsv/identity/types'
    autoload :CertifierInfo,        'bsv/identity/types'
    autoload :IdentityCertificate,  'bsv/identity/types'
    autoload :ClientOptions,        'bsv/identity/types'
    autoload :Constants,            'bsv/identity/constants'
    autoload :IdentityParser,       'bsv/identity/identity_parser'
    autoload :Client,               'bsv/identity/client'
  end
end
