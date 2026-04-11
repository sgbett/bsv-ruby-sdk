# frozen_string_literal: true

module BSV
  # Registry module for managing on-chain definitions for protocols, baskets,
  # and certificate types via PushDrop-based UTXOs on the BSV overlay network.
  #
  # Registry operators use this module to establish and manage canonical
  # references for basket IDs, protocol specifications, and certificate schemas.
  module Registry
    autoload :DefinitionType, 'bsv/registry/types'
    autoload :CertificateFieldDescriptor, 'bsv/registry/types'
    autoload :BasketDefinitionData, 'bsv/registry/types'
    autoload :ProtocolDefinitionData, 'bsv/registry/types'
    autoload :CertificateDefinitionData, 'bsv/registry/types'
    autoload :RegisteredDefinition, 'bsv/registry/types'
    autoload :Constants,           'bsv/registry/constants'
    autoload :Client,              'bsv/registry/client'
  end
end
