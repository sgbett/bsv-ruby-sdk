# frozen_string_literal: true

module BSV
  module MCP
    autoload :Config, 'bsv/mcp/config'
    autoload :Server, 'bsv/mcp/server'

    module Tools
      autoload :GenerateKey, 'bsv/mcp/tools/generate_key'
      autoload :DecodeTx,    'bsv/mcp/tools/decode_tx'
      autoload :FetchUtxos,  'bsv/mcp/tools/fetch_utxos'
      autoload :FetchTx,     'bsv/mcp/tools/fetch_tx'
    end
  end
end
