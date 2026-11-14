# frozen_string_literal: true

require 'mcp'

module BSV
  module MCP
    autoload :Config, 'bsv/mcp/config'
    autoload :Secret, 'bsv/mcp/secret'
    autoload :Server, 'bsv/mcp/server'

    module Tools
      autoload :Helpers,         'bsv/mcp/tools/helpers'
      autoload :AddressInput,    'bsv/mcp/tools/address_input'
      autoload :GenerateKey,     'bsv/mcp/tools/generate_key'
      autoload :DecodeTx,        'bsv/mcp/tools/decode_tx'
      autoload :FetchUtxos,      'bsv/mcp/tools/fetch_utxos'
      autoload :FetchTx,         'bsv/mcp/tools/fetch_tx'
      autoload :CheckBalance,    'bsv/mcp/tools/check_balance'
      autoload :BroadcastP2pkh,  'bsv/mcp/tools/broadcast_p2pkh'
    end
  end
end
