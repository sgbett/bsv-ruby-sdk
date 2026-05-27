# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +reveal_specific_key_linkage+ call (call byte 10).
      #
      # Port of go-sdk/wallet/serializer/reveal_specific_key_linkage.go.
      module RevealSpecificKeyLinkage
        PUBKEY_SIZE = 33

        # Args wire layout:
        #   [key-related params: protocol + key_id + counterparty + privileged]
        #   [33 bytes: verifier compressed pubkey]
        module Args
          module_function

          def serialize(args)
            BSV::Wallet::Wire::Validation.wallet_protocol!('protocol_id', args[:protocol_id])
            BSV::Wallet::Wire::Validation.key_id_string_1_to_800!('key_id', args[:key_id])
            BSV::Wallet::Wire::Validation.wallet_counterparty!('counterparty', args[:counterparty])

            verifier = args[:verifier]
            raise BSV::Wallet::InvalidParameterError.new('verifier', 'a 33-byte binary pubkey or 66-char hex') unless verifier

            w = BSV::Wallet::Wire::Writer.new
            Common.write_key_related_params(
              w,
              protocol_id: args[:protocol_id],
              key_id: args[:key_id],
              counterparty: args[:counterparty],
              privileged: args[:privileged],
              privileged_reason: args[:privileged_reason]
            )
            w.write_bytes(pubkey_bytes(verifier))
            w.buf
          end

          def deserialize(bytes)
            r = BSV::Wallet::Wire::Reader.new(bytes)
            params   = Common.read_key_related_params(r)
            verifier = r.read_bytes(PUBKEY_SIZE)
            params.merge(verifier: verifier)
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
        #   [1 byte: security_level][VarInt protocol_name_len][protocol_name bytes]
        #   [VarInt key_id_len][key_id bytes]
        #   [VarInt encrypted_linkage_len][encrypted_linkage bytes]
        #   [VarInt encrypted_linkage_proof_len][encrypted_linkage_proof bytes]
        #   [1 byte: proof_type]
        module Result
          module_function

          def serialize(result)
            w = BSV::Wallet::Wire::Writer.new
            w.write_bytes(pubkey_bytes(result[:prover]))
            w.write_bytes(pubkey_bytes(result[:verifier]))
            w.write_bytes(pubkey_bytes(result[:counterparty]))
            Common.write_protocol(w, result[:protocol_id])
            key_id_bytes = result[:key_id].to_s.b
            w.write_varint(key_id_bytes.bytesize)
            w.write_bytes(key_id_bytes)
            encrypted_linkage = Common.to_binary(result[:encrypted_linkage])
            w.write_varint(encrypted_linkage.bytesize)
            w.write_bytes(encrypted_linkage)
            encrypted_linkage_proof = Common.to_binary(result[:encrypted_linkage_proof])
            w.write_varint(encrypted_linkage_proof.bytesize)
            w.write_bytes(encrypted_linkage_proof)
            w.write_byte(result[:proof_type].to_i)
            w.buf
          end

          def deserialize(bytes)
            r = BSV::Wallet::Wire::Reader.new(bytes)
            prover       = r.read_bytes(PUBKEY_SIZE)
            verifier     = r.read_bytes(PUBKEY_SIZE)
            counterparty = r.read_bytes(PUBKEY_SIZE)
            protocol_id  = Common.read_protocol(r)
            key_id_len   = r.read_varint
            key_id       = r.read_bytes(key_id_len).force_encoding('UTF-8')
            el_len = r.read_varint
            encrypted_linkage = r.read_bytes(el_len)
            elp_len = r.read_varint
            encrypted_linkage_proof = r.read_bytes(elp_len)
            proof_type = r.read_byte
            {
              prover: prover,
              verifier: verifier,
              counterparty: counterparty,
              protocol_id: protocol_id,
              key_id: key_id,
              encrypted_linkage: encrypted_linkage,
              encrypted_linkage_proof: encrypted_linkage_proof,
              proof_type: proof_type
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
