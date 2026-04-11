# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Generates a new random BSV private key and derives the corresponding
      # public key and address.
      #
      # Each invocation produces a cryptographically fresh key — the result is
      # never reused or persisted by the server. Store the WIF securely; it
      # cannot be recovered from the address alone.
      class GenerateKey < ::MCP::Tool
        tool_name 'generate_key'

        description <<~DESC.strip
          Generate a new random BSV private key.

          Returns the private key in WIF (Wallet Import Format), the compressed
          public key as hex, and the corresponding P2PKH address for the
          configured network.

          IMPORTANT: A new key is generated on every call. The WIF is never
          stored by the server — save it immediately in secure storage.
          Losing the WIF means losing access to any funds sent to the address.

          The address format is network-specific: mainnet addresses start with
          '1', testnet addresses start with 'm' or 'n'.
        DESC

        input_schema(
          type: 'object',
          properties: {
            network: {
              type: 'string',
              enum: %w[mainnet testnet],
              description: 'Network to generate the key for. Overrides the server default.'
            }
          }
        )

        def self.call(network: nil, server_context: nil)
          net_sym = Helpers.resolve_network_sym(network, server_context)

          key = BSV::Primitives::PrivateKey.generate
          pub = key.public_key

          result = {
            wif: key.to_wif(network: net_sym),
            public_key_hex: pub.to_hex,
            address: pub.address(network: net_sym),
            network: net_sym.to_s
          }

          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(result.to_json)],
            structured_content: result
          )
        end
      end
    end
  end
end
