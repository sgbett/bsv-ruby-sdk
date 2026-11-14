# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Returns the total confirmed and unconfirmed balance for a BSV address
      # or WIF private key, along with the individual UTXOs.
      #
      # Accepts either a WIF-encoded private key (from which the address is
      # derived) or a plain P2PKH address string. The tool auto-detects the
      # input type from its Base58Check version byte. Either must be for the
      # call's network, and nothing is sent to WhatsOnChain otherwise.
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

          Note: addresses and keys are network-specific. An address or WIF for
          the other network is rejected without any request being made.
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
          net_sym = Helpers.resolve_network_sym(network, server_context)
          address = AddressInput.resolve(address_or_wif, net_sym, allow_wif: true)

          provider = BSV::Network::Providers::WhatsOnChain.default(network: net_sym)
          utxo_result = provider.call(:get_utxos_all, address)

          unless utxo_result.http_success?
            code = utxo_result.code
            msg = utxo_result.message
            msg = "#{msg} (HTTP #{code})" if code
            return Helpers.error_response(msg)
          end

          utxos = utxo_result.data.map do |entry|
            BSV::Network::UTXO.new(
              tx_hash: entry['tx_hash'], tx_pos: entry['tx_pos'],
              value: entry['value'], height: entry['height']
            )
          end

          balance = utxos.sum(&:satoshis)
          result = {
            address: address,
            network: net_sym.to_s,
            balance_satoshis: balance,
            utxo_count: utxos.length,
            utxos: utxos.map { |u| Helpers.utxo_to_h(u) }
          }

          Helpers.json_response(result)
        rescue ArgumentError => e
          Helpers.error_response(e.message)
        end
      end
    end
  end
end
