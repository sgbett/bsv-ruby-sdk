# frozen_string_literal: true

module BSV
  module MCP
    module Tools
      # Builds, signs, and broadcasts a simple P2PKH payment transaction.
      #
      # Fetches UTXOs for the sender's address, constructs a transaction
      # with one payment output and one change output, signs all inputs
      # with the provided private key, and submits it in Extended Format
      # (EF/BRC-30) through the broadcaster chosen by {.select_broadcaster}.
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
          6. Submits it in Extended Format (EF/BRC-30) to the broadcaster
          7. Returns the txid, the service's transaction status and the raw hex

          Where it broadcasts: the GorillaPool provider's broadcaster for the
          network, or the ARC endpoint the server was configured with
          (BSV_ARC_URL) for calls on the server's own network.

          Parameters:
          - wif: sender's private key in WIF format. The key is used only
            for this call and is never stored by the server. It must be for
            the network being used.
          - to_address: recipient P2PKH address for the network being used
          - satoshis: amount to send in satoshis (must be > 0)
          - network: 'mainnet' or 'testnet' — overrides the server default

          Returns:
          - txid: the transaction ID, computed by this tool
          - tx_status: the transaction status reported by the broadcast
            service (e.g. 'RECEIVED', 'SEEN_ON_NETWORK'), when it gives one.
            States such as RECEIVED or STORED only mean the service has the
            transaction; they do NOT mean the network has accepted it. Check
            the transaction later (e.g. with fetch_tx) before relying on it.
          - hex: the raw transaction hex (plain format, not EF)

          Error conditions (returned as error responses, not raised):
          - Invalid WIF key, or a WIF for a different network
          - Recipient that is not a P2PKH address for the network
          - No UTXOs found for sender
          - Insufficient funds (balance < satoshis + estimated fee)
          - Broadcast failure, a rejected status, or a service reply naming a
            different txid. Once the transaction has been built, the error
            response also carries its txid.
          Change below the dust limit is absorbed into the fee.

          Technical notes:
          - All inputs have source_satoshis and source_locking_script set,
            enabling Extended Format (EF/BRC-30) submission.
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

        def self.call(wif:, to_address:, satoshis:, network: nil, server_context: nil)
          txid = nil
          net_sym = Helpers.resolve_network_sym(network, server_context)
          broadcaster = select_broadcaster(net_sym, server_context)

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
          txid = tx.txid_hex # MCP tool boundary: display-order hex for human consumption

          broadcast_result = broadcaster.call(:broadcast, tx)
          unless broadcast_result.http_success?
            message = Helpers.scrub("Broadcast failed: #{broadcast_result.message}", server_context)
            return Helpers.error_response(message, txid: txid)
          end

          data = broadcast_result.data || {}
          problem = broadcast_problem(data, txid)
          return Helpers.error_response(Helpers.scrub(problem, server_context), txid: txid) if problem

          result = { txid: txid, tx_status: data['txStatus'], hex: tx.to_hex }.compact

          ::MCP::Tool::Response.new(
            [::MCP::Content::Text.new(result.to_json)],
            structured_content: result
          )
        rescue StandardError => e
          # Catch broadly so MCP returns a structured error rather than
          # crashing the tool handler on unexpected exception types
          # (e.g. NoMethodError on nil WIF input, encoding errors, etc.).
          Helpers.error_response(Helpers.scrub(e.message, server_context), txid: txid)
        end

        # Inspect a 2xx broadcast reply for signs that the transaction was not
        # accepted. The Arcade parser only rejects +REJECTED+, so the wider ARC
        # rejection set is checked here too.
        #
        # @return [String, nil] a description of the problem, or nil
        # @api private
        def self.broadcast_problem(data, computed_txid)
          tx_status = data['txStatus'].to_s.upcase
          rejected = BSV::Network::Protocols::ARC::REJECTED_STATUSES.include?(tx_status) ||
                     tx_status.include?(BSV::Network::Protocols::ARC::ORPHAN_MARKER)
          return "Broadcast rejected: transaction status #{tx_status}" if rejected

          reported = data['txid']
          return if reported.nil? || reported.to_s.downcase == computed_txid

          'Broadcast service reported a different txid from the one computed for this transaction'
        end
        private_class_method :broadcast_problem

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
          tx = BSV::Transaction::Tx.new

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

        # Choose the protocol that broadcasts the transaction.
        #
        # The configured ARC endpoint (+BSV_ARC_URL+) is used only for calls on
        # the server's own network, so a transaction for the other network never
        # reaches it. Its key is sent there and nowhere else: every other call
        # goes to the GorillaPool provider's broadcaster, which takes no key and
        # is built without any option derived from the context.
        #
        # @param net_sym [Symbol] the call's network (:mainnet or :testnet)
        # @param server_context [Hash, MCP::ServerContext, nil]
        # @return [BSV::Network::Protocol]
        # @api private
        def self.select_broadcaster(net_sym, server_context)
          arc_url = Helpers.context_value(server_context, :arc_url)
          server_network = Helpers.context_value(server_context, :bsv_network)

          if !arc_url.to_s.strip.empty? && net_sym.to_s == server_network
            api_key = Secret.reveal(Helpers.context_value(server_context, :arc_api_key))
            return BSV::Network::Protocols::ARC.new(base_url: arc_url, api_key: api_key)
          end

          BSV::Network::Providers::GorillaPool.default(testnet: net_sym == :testnet).protocol_for(:broadcast)
        end
        private_class_method :select_broadcaster
      end
    end
  end
end
