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
          net = resolve_network(network, server_context)
          net_sym = net == 'testnet' ? :testnet : :mainnet

          key = BSV::Primitives::PrivateKey.generate
          pub = key.public_key

          result = {
            wif: key.to_wif(network: net_sym),
            public_key_hex: pub.to_hex,
            address: pub.address(network: net_sym),
            network: net
          }

          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(result.to_json)],
            structured_content: result
          )
        end

        # @api private
        def self.resolve_network(network_arg, server_context)
          return network_arg if network_arg

          # Extract from server_context if it carries BSV config
          return server_context[:bsv_network] if server_context.is_a?(Hash) && server_context[:bsv_network]

          BSV::MCP::Config::MAINNET
        end
        private_class_method :resolve_network
      end
    end
  end
end
