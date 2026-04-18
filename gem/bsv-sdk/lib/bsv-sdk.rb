# frozen_string_literal: true

require_relative 'bsv/version'

module BSV
  autoload :Primitives,  'bsv/primitives'
  autoload :Script,      'bsv/script'
  autoload :Transaction, 'bsv/transaction'
  autoload :Network,     'bsv/network'
  require_relative 'bsv/wallet' # eager — BSV::Wallet may be pre-defined by bsv-wallet gemspec
  autoload :Auth,        'bsv/auth'
  autoload :Overlay,     'bsv/overlay'
  autoload :Identity,    'bsv/identity'
  autoload :Registry,    'bsv/registry'
  autoload :MCP,         'bsv/mcp'
  autoload :Messages,    'bsv/messages'
  autoload :WireFormat,  'bsv/wire_format'
end
