# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +reveal_counterparty_key_linkage+ call (call byte 9).
      #
      # Port of go-sdk/wallet/serializer/reveal_counterparty_key_linkage.go.
      module RevealCounterpartyKeyLinkage
        PUBKEY_SIZE = 33

        # Args wire layout:
        #   [privileged params]
        #   [33 bytes: counterparty compressed pubkey]
        #   [33 bytes: verifier compressed pubkey]
        module Args
          module_function

          def serialize(args)
            counterparty = args[:counterparty]
            verifier     = args[:verifier]
            raise BSV::Wallet::InvalidParameterError.new('counterparty', 'a 33-byte binary pubkey or 66-char hex') unless counterparty
            raise BSV::Wallet::InvalidParameterError.new('verifier', 'a 33-byte binary pubkey or 66-char hex') unless verifier

            w = BSV::Wallet::Wire::Writer.new
            Common.write_privileged_params(w, args[:privileged], args[:privileged_reason])
            w.write_bytes(pubkey_bytes(counterparty))
            w.write_bytes(pubkey_bytes(verifier))
            w.buf
          end

          def deserialize(bytes)
            r = BSV::Wallet::Wire::Reader.new(bytes)
            privileged, reason = Common.read_privileged_params(r)
            counterparty = r.read_bytes(PUBKEY_SIZE)
            verifier     = r.read_bytes(PUBKEY_SIZE)
            {
              privileged: privileged,
              privileged_reason: reason,
              counterparty: counterparty,
              verifier: verifier
            }
          end

          def pubkey_bytes(value)
            return value.b if value.is_a?(String) && value.bytesize == PUBKEY_SIZE

            [value.to_s].pack('H*')
          end
          private_class_method :pubkey_bytes
        end

        # Result wire layout:
        #   [33 bytes: prover pubkey]
        #   [33 bytes: verifier pubkey]
        #   [33 bytes: counterparty pubkey]
        #   [VarInt revelation_time_len][revelation_time bytes]
        #   [VarInt encrypted_linkage_len][encrypted_linkage bytes]
        #   [VarInt encrypted_linkage_proof_len][encrypted_linkage_proof bytes]
        module Result
          module_function

          def serialize(result)
            w = BSV::Wallet::Wire::Writer.new
            w.write_bytes(pubkey_bytes(result[:prover]))
            w.write_bytes(pubkey_bytes(result[:verifier]))
            w.write_bytes(pubkey_bytes(result[:counterparty]))
            w.write_str_with_varint_len(result[:revelation_time].to_s)
            encrypted_linkage = result[:encrypted_linkage] || ''.b
            w.write_varint(encrypted_linkage.bytesize)
            w.write_bytes(encrypted_linkage)
            encrypted_linkage_proof = result[:encrypted_linkage_proof] || ''.b
            w.write_varint(encrypted_linkage_proof.bytesize)
            w.write_bytes(encrypted_linkage_proof)
            w.buf
          end

          def deserialize(bytes)
            r = BSV::Wallet::Wire::Reader.new(bytes)
            prover       = r.read_bytes(PUBKEY_SIZE)
            verifier     = r.read_bytes(PUBKEY_SIZE)
            counterparty = r.read_bytes(PUBKEY_SIZE)
            revelation_time = r.read_str_with_varint_len
            el_len = r.read_varint
            encrypted_linkage = r.read_bytes(el_len)
            elp_len = r.read_varint
            encrypted_linkage_proof = r.read_bytes(elp_len)
            {
              prover: prover,
              verifier: verifier,
              counterparty: counterparty,
              revelation_time: revelation_time,
              encrypted_linkage: encrypted_linkage,
              encrypted_linkage_proof: encrypted_linkage_proof
            }
          end

          def pubkey_bytes(value)
            return value.b if value.is_a?(String) && value.bytesize == PUBKEY_SIZE

            [value.to_s].pack('H*')
          end
          private_class_method :pubkey_bytes
        end
      end
    end
  end
end
