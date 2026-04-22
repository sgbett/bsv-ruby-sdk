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

  autoload :WireFormat,  'bsv/wire_format'
end
