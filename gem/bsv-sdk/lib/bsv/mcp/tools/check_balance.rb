# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Returns the total confirmed and unconfirmed balance for a BSV address
      # or WIF private key, along with the individual UTXOs.
      #
      # Accepts either a WIF-encoded private key (from which the address is
      # derived) or a plain P2PKH address string. The tool auto-detects the
      # input type via a try/rescue on +PrivateKey.from_wif+.
      class CheckBalance < ::MCP::Tool
        tool_name 'check_balance'

        description <<~DESC.strip
          Check the BSV balance for an address or WIF private key.

          Accepts either a WIF-encoded private key (auto-derives the address)
          or a P2PKH address string directly. The tool detects which was
          supplied automatically.

          Parameters:
          - address_or_wif: a BSV P2PKH address (mainnet starts with '1';
            testnet starts with 'm' or 'n') OR a WIF private key (mainnet
            starts with '5', 'K', or 'L'; testnet starts with '9' or 'c')
          - network: 'mainnet' or 'testnet' — overrides the server default

          Returns:
          - address: the resolved P2PKH address
          - balance_satoshis: total balance across all UTXOs
          - utxo_count: number of unspent outputs
          - utxos: array of { tx_hash, tx_pos, satoshis, height } objects

          Note: balance is the sum of all UTXOs; it does not distinguish
          confirmed from unconfirmed. A height of 0 indicates an unconfirmed
          (mempool) UTXO.

          Note: addresses are network-specific. A mainnet address queried
          against testnet (or vice versa) will return no results or an error.
        DESC

        input_schema(
          type: 'object',
          properties: {
            address_or_wif: {
              type: 'string',
              description: 'BSV P2PKH address or WIF private key to check.'
            },
            network: {
              type: 'string',
              enum: %w[mainnet testnet],
              description: 'Network to query. Overrides the server default.'
            }
          },
          required: ['address_or_wif']
        )

        def self.call(address_or_wif:, network: nil, server_context: nil)
          net_sym = resolve_network_sym(network, server_context)
          address = resolve_address(address_or_wif, net_sym)

          woc = BSV::Network::WhatsOnChain.new(network: net_sym)
          utxos = woc.fetch_utxos(address)

          balance = utxos.sum(&:satoshis)
          result = {
            address: address,
            network: net_sym.to_s,
            balance_satoshis: balance,
            utxo_count: utxos.length,
            utxos: utxos.map { |u| utxo_to_h(u) }
          }

          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(result.to_json)],
            structured_content: result
          )
        rescue ArgumentError => e
          error_result = { error: e.message }
          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(error_result.to_json)],
            error: true
          )
        rescue BSV::Network::ChainProviderError => e
          error_result = { error: e.message, status_code: e.status_code }
          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(error_result.to_json)],
            error: true
          )
        end

        # @api private
        def self.resolve_network_sym(network_arg, server_context)
          net = network_arg
          net = server_context[:bsv_network] if net.nil? && server_context.is_a?(Hash) && server_context[:bsv_network]
          net == 'testnet' ? :testnet : :mainnet
        end
        private_class_method :resolve_network_sym

        # Resolve a WIF key or address string to a P2PKH address.
        #
        # Attempts WIF decoding first; if that raises ArgumentError, treats the
        # input as a plain address string.
        # @api private
        def self.resolve_address(address_or_wif, net_sym)
          key = BSV::Primitives::PrivateKey.from_wif(address_or_wif)
          key.public_key.address(network: net_sym)
        rescue ArgumentError
          address_or_wif
        end
        private_class_method :resolve_address

        def self.utxo_to_h(utxo)
          {
            tx_hash: utxo.tx_hash,
            tx_pos: utxo.tx_pos,
            satoshis: utxo.satoshis,
            height: utxo.height
          }
        end
        private_class_method :utxo_to_h
      end
    end
  end
end
