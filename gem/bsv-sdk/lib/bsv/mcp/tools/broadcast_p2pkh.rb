# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Builds, signs, and broadcasts a simple P2PKH payment transaction.
      #
      # Fetches UTXOs for the sender's address, constructs a transaction
      # with one payment output and one change output, signs all inputs
      # with the provided private key, and submits to ARC in Extended
      # Format (EF/BRC-30).
      #
      # This is the most complex MCP tool: it orchestrates WIF → PrivateKey
      # → PublicKey → address → UTXO fetch → tx build → sign → broadcast.
      class BroadcastP2pkh < ::MCP::Tool
        tool_name 'broadcast_p2pkh'

        description <<~DESC.strip
          Build, sign, and broadcast a P2PKH payment transaction.

          WARNING: This tool broadcasts a REAL transaction to the BSV network
          and SPENDS REAL SATOSHIS. Use testnet for testing.

          The tool:
          1. Derives the sender address from the WIF private key
          2. Fetches UTXOs for the sender address via WhatsOnChain
          3. Selects sufficient UTXOs (greedy: largest first)
          4. Builds a transaction with a payment output and a change output
          5. Signs all inputs with the WIF key (P2PKH, SIGHASH_ALL|FORKID)
          6. Submits to ARC in Extended Format (EF/BRC-30)
          7. Returns txid, status, and the raw hex

          Parameters:
          - wif: sender's private key in WIF format. The key is used only
            for this call and is never stored by the server.
          - to_address: recipient P2PKH address
          - satoshis: amount to send in satoshis (must be > 0)
          - network: 'mainnet' or 'testnet' — overrides the server default

          Returns:
          - txid: the broadcast transaction ID
          - tx_status: ARC status string (e.g. 'SEEN_ON_NETWORK')
          - hex: the raw transaction hex (plain format, not EF)

          Error conditions (returned as error responses, not raised):
          - Invalid WIF key
          - No UTXOs found for sender
          - Insufficient funds (balance < satoshis + estimated fee)
          - Change below dust (546 sat): change is absorbed into the fee
          - ARC broadcast rejection

          Technical notes:
          - All inputs have source_satoshis and source_locking_script set,
            enabling Extended Format (EF/BRC-30) submission to ARC.
          - Fee model: SatoshisPerKilobyte at 100 sat/kB (SDK default).
          - Change returns to the sender address.
          - UTXO selection: greedy descending by value.
        DESC

        input_schema(
          type: 'object',
          properties: {
            wif: {
              type: 'string',
              description: 'Sender private key in WIF format.'
            },
            to_address: {
              type: 'string',
              description: 'Recipient P2PKH address.'
            },
            satoshis: {
              type: 'integer',
              description: 'Amount to send in satoshis.',
              minimum: 1
            },
            network: {
              type: 'string',
              enum: %w[mainnet testnet],
              description: 'Network to broadcast on. Overrides the server default.'
            }
          },
          required: %w[wif to_address satoshis]
        )

        # Minimum output value to avoid dust rejection.
        DUST_THRESHOLD = 546

        def self.call(wif:, to_address:, satoshis:, network: nil, server_context: nil)
          net_sym = Helpers.resolve_network_sym(network, server_context)

          private_key = BSV::Primitives::PrivateKey.from_wif(wif)
          sender_address = private_key.public_key.address(network: net_sym)

          woc = BSV::Network::Providers::WhatsOnChain.default(network: net_sym)
          utxo_result = woc.call(:get_utxos_all, sender_address)
          return Helpers.error_response("UTXO fetch failed: #{utxo_result.message}") unless utxo_result.http_success?

          all_utxos = utxo_result.data.map do |entry|
            BSV::Network::UTXO.new(
              tx_hash: entry['tx_hash'], tx_pos: entry['tx_pos'],
              value: entry['value'], height: entry['height']
            )
          end

          return Helpers.error_response('No UTXOs found for sender address — the address may have no funds') if all_utxos.empty?

          # Greedy UTXO selection: sort descending, take until sufficient
          sorted = all_utxos.sort_by { |u| -u.satoshis }
          selected = select_utxos(sorted, satoshis)
          return Helpers.error_response("Insufficient funds — available: #{all_utxos.sum(&:satoshis)} satoshis") if selected.nil?

          tx = build_transaction(selected, satoshis, to_address, sender_address, private_key)

          arc = build_arc(net_sym, server_context)
          arc_result = arc.call(:broadcast, tx)
          return Helpers.error_response("Broadcast failed: #{arc_result.message}") unless arc_result.http_success?

          data = arc_result.data || {}
          result = {
            txid: data['txid'], # MCP tool boundary: display-order hex from Arcade response (present on re-submission)
            tx_status: data['status'],
            state: data['state'],
            hex: tx.to_hex
          }.compact

          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(result.to_json)],
            structured_content: result
          )
        rescue ArgumentError => e
          Helpers.error_response(e.message)
        end

        # Select UTXOs greedily until the total meets or exceeds the target.
        # Returns nil when total funds are insufficient.
        # @api private
        def self.select_utxos(sorted_utxos, target_satoshis)
          selected = []
          total = 0
          sorted_utxos.each do |utxo|
            selected << utxo
            total += utxo.satoshis
            break if total >= target_satoshis
          end
          # We may still not have enough — caller checks nil return
          total >= target_satoshis ? selected : nil
        end
        private_class_method :select_utxos

        # Build, fee-compute, and sign the transaction.
        # @api private
        def self.build_transaction(selected_utxos, satoshis, to_address, sender_address, private_key)
          tx = BSV::Transaction::Transaction.new

          # Wire inputs with EF metadata (source_satoshis + source_locking_script)
          selected_utxos.each do |utxo|
            locking_script = p2pkh_lock_for(sender_address)
            input = BSV::Transaction::TransactionInput.new(
              prev_wtxid: BSV::Transaction::TransactionInput.wtxid_from_hex(utxo.tx_hash),
              prev_tx_out_index: utxo.tx_pos
            )
            input.source_satoshis = utxo.satoshis
            input.source_locking_script = locking_script
            input.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
            tx.add_input(input)
          end

          # Payment output
          tx.add_output(BSV::Transaction::TransactionOutput.new(
                          satoshis: satoshis,
                          locking_script: p2pkh_lock_for(to_address)
                        ))

          # Change output (marked as change so tx.fee distributes into it)
          tx.add_output(BSV::Transaction::TransactionOutput.new(
                          satoshis: 0,
                          locking_script: p2pkh_lock_for(sender_address),
                          change: true
                        ))

          # Compute fee and distribute change; removes change output when dust
          tx.fee

          # Guard: if total outputs exceed inputs the transaction is invalid
          if tx.total_output_satoshis > tx.total_input_satoshis
            raise ArgumentError,
                  "Insufficient funds: inputs #{tx.total_input_satoshis} sat, " \
                  "outputs #{tx.total_output_satoshis} sat (including fee)"
          end

          # Sign all inputs via their P2PKH templates
          tx.sign_all

          tx
        end
        private_class_method :build_transaction

        # Build a P2PKH locking script for the given address.
        # @api private
        def self.p2pkh_lock_for(address)
          hash160 = BSV::Primitives::Base58.check_decode(address)[1..]
          BSV::Script::Script.p2pkh_lock(hash160)
        end
        private_class_method :p2pkh_lock_for

        # Build an ARC protocol instance using server config when available.
        # @api private
        def self.build_arc(net_sym, server_context)
          testnet = net_sym == :testnet
          opts = {}
          opts[:api_key] = server_context[:arc_api_key] if server_context.is_a?(Hash) && server_context[:arc_api_key]
          provider = BSV::Network::Providers::GorillaPool.default(testnet: testnet, **opts)
          provider.protocol_for(:broadcast)
        end
        private_class_method :build_arc
      end
    end
  end
end
