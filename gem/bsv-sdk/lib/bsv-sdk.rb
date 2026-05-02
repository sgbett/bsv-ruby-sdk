# frozen_string_literal: true

require_relative 'bsv/version'

module BSV
  autoload :Primitives,  'bsv/primitives'
  autoload :Script,      'bsv/script'
  autoload :Transaction, 'bsv/transaction'
  autoload :Network,     'bsv/network'
  autoload :Auth,        'bsv/auth'
  autoload :Overlay,     'bsv/overlay'
  autoload :Identity,    'bsv/identity'
  autoload :Registry,    'bsv/registry'
  autoload :MCP,         'bsv/mcp'

  # Wallet is loaded eagerly to avoid load-path shadowing when bsv-wallet is
  # also in the bundle (bsv-wallet/lib/bsv/wallet.rb would otherwise win).
  require_relative 'bsv/wallet'
  autoload :WireFormat, 'bsv/wire_format'
end
