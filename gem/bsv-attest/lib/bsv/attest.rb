# frozen_string_literal: true

module BSV
  module Attest
    autoload :BroadcastError,    'bsv/attest/broadcast_error'
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

      def publish(data, wallet: nil, description: nil)
        w = wallet || configuration.wallet
        raise ArgumentError, 'wallet is required' unless w

        digest = hash(data)
        script = BSV::Script::Script.op_return(digest)

        desc = description || 'Attest data hash to chain'

        result = w.create_action(
          {
            description: desc,
            outputs: [{
              locking_script: script.to_hex,
              satoshis: 0,
              output_description: 'Attestation hash'
            }],
            options: { randomize_outputs: false }
          }
        )

        raise BroadcastError, result[:broadcast_error] if result[:broadcast_error]

        Response.new(hash: digest, txid: result[:txid])
      end

      def verify(data, txid, provider: nil)
        BSV::Primitives::Hex.validate_dtxid_hex!(txid, name: 'verify txid')
        p = provider || configuration.provider
        raise ArgumentError, 'provider is required' unless p

        digest = hash(data)

        tx = p.fetch_transaction(txid)

        tx.outputs.each do |output|
          script = output.locking_script
          next unless script.op_return?

          # Use op_return_data which correctly re-parses the tail after F3.1's
          # OP_RETURN termination fix (the raw tail is now in one chunk).
          items = script.op_return_data
          next if items.nil?

          return true if items.include?(digest)
        end

        raise VerificationError, 'hash not found in transaction outputs'
      end
    end
  end
end
