# frozen_string_literal: true

module BSV
  module Attest
    autoload :Configuration,     'bsv/attest/configuration'
    autoload :Response,          'bsv/attest/response'
    autoload :VerificationError, 'bsv/attest/verification_error'
    autoload :VERSION,           'bsv/attest/version'

    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def reset_configuration!
        @configuration = Configuration.new
      end

      def hash(data)
        BSV::Primitives::Digest.sha256(data)
      end

      def publish(data, wallet: nil, broadcaster: nil)
        w = wallet || configuration.wallet
        b = broadcaster || configuration.broadcaster
        raise ArgumentError, 'wallet is required' unless w
        raise ArgumentError, 'broadcaster is required' unless b

        digest = hash(data)

        script = BSV::Script::Script.op_return(digest)
        output = BSV::Transaction::TransactionOutput.new(satoshis: 0, locking_script: script)

        tx = BSV::Transaction::Transaction.new
        tx.add_output(output)

        w.fund_and_sign(tx)

        broadcast_response = b.broadcast(tx)

        Response.new(hash: digest, transaction: tx, txid: broadcast_response.txid)
      end

      def verify(data, txid, provider: nil)
        p = provider || configuration.provider
        raise ArgumentError, 'provider is required' unless p

        digest = hash(data)

        tx = p.fetch_transaction(txid)

        tx.outputs.each do |output|
          chunks = output.locking_script.chunks
          next if chunks.length < 3
          next unless chunks[0].opcode == BSV::Script::Opcodes::OP_FALSE
          next unless chunks[1].opcode == BSV::Script::Opcodes::OP_RETURN

          chunks[2..].each do |chunk|
            return true if chunk.data == digest
          end
        end

        raise VerificationError, 'hash not found in transaction outputs'
      end
    end
  end
end
