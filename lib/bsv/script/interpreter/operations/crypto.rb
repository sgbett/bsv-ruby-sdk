# frozen_string_literal: true

module BSV
  module Script
    class Interpreter
      module Operations
        # Cryptographic operations: hash functions, CHECKSIG, and CHECKMULTISIG.
        module Crypto
          private

          # --- Hash operations ---

          def op_ripemd160
            @dstack.push_bytes(BSV::Primitives::Digest.ripemd160(@dstack.pop_bytes))
          end

          def op_sha1
            @dstack.push_bytes(BSV::Primitives::Digest.sha1(@dstack.pop_bytes))
          end

          def op_sha256
            @dstack.push_bytes(BSV::Primitives::Digest.sha256(@dstack.pop_bytes))
          end

          def op_hash160
            @dstack.push_bytes(BSV::Primitives::Digest.hash160(@dstack.pop_bytes))
          end

          def op_hash256
            @dstack.push_bytes(BSV::Primitives::Digest.sha256d(@dstack.pop_bytes))
          end

          # --- Code separator ---

          # OP_CODESEPARATOR: mark subscript boundary for sighash
          def op_codeseparator
            @last_code_sep = @current_chunk_idx + 1
          end

          # --- Signature verification ---

          # OP_CHECKSIG: verify a single signature
          def op_checksig
            pubkey_bytes = @dstack.pop_bytes
            full_sig = @dstack.pop_bytes

            if full_sig.empty?
              @dstack.push_bool(false)
              return
            end

            result = verify_checksig(full_sig, pubkey_bytes)

            # NULLFAIL: non-empty signature that failed verification
            raise ScriptError.new(ScriptErrorCode::SIG_NULLFAIL, 'non-empty signature failed verification') unless result

            @dstack.push_bool(true)
          end

          # OP_CHECKSIGVERIFY: OP_CHECKSIG then OP_VERIFY
          def op_checksigverify
            op_checksig
            return if @dstack.pop_bool

            raise ScriptError.new(ScriptErrorCode::CHECKSIGVERIFY_FAILED, 'OP_CHECKSIGVERIFY failed')
          end

          # OP_CHECKMULTISIG: verify M-of-N signatures
          def op_checkmultisig
            num_pubkeys = @dstack.pop_int.to_i32
            if num_pubkeys.negative? || num_pubkeys > 20
              raise ScriptError.new(ScriptErrorCode::INVALID_PUBKEY_COUNT, "invalid pubkey count: #{num_pubkeys}")
            end

            pubkeys = Array.new(num_pubkeys) { @dstack.pop_bytes }

            num_sigs = @dstack.pop_int.to_i32
            if num_sigs.negative? || num_sigs > num_pubkeys
              raise ScriptError.new(ScriptErrorCode::INVALID_SIG_COUNT, "invalid signature count: #{num_sigs}")
            end

            signatures = Array.new(num_sigs) { @dstack.pop_bytes }

            # Dummy element (off-by-one bug compatibility)
            dummy = @dstack.pop_bytes
            raise ScriptError.new(ScriptErrorCode::SIG_NULLDUMMY, 'CHECKMULTISIG dummy element must be empty') unless dummy.empty?

            success = multisig_match?(signatures, pubkeys)

            # NULLFAIL: if failed, all signatures must be empty
            unless success
              signatures.each do |sig|
                raise ScriptError.new(ScriptErrorCode::SIG_NULLFAIL, 'non-empty signature failed verification') unless sig.empty?
              end
            end

            @dstack.push_bool(success)
          end

          # OP_CHECKMULTISIGVERIFY: OP_CHECKMULTISIG then OP_VERIFY
          def op_checkmultisigverify
            op_checkmultisig
            return if @dstack.pop_bool

            raise ScriptError.new(ScriptErrorCode::CHECKMULTISIGVERIFY_FAILED, 'OP_CHECKMULTISIGVERIFY failed')
          end

          # --- Helpers ---

          # Verify a single signature against a public key.
          def verify_checksig(full_sig, pubkey_bytes)
            sighash_type = full_sig.getbyte(full_sig.bytesize - 1)
            sig_bytes = full_sig.byteslice(0, full_sig.bytesize - 1)

            validate_sighash_type!(sighash_type)
            sig = parse_der_signature!(sig_bytes)
            validate_pubkey_encoding!(pubkey_bytes)

            return false unless @tx

            pubkey = BSV::Primitives::PublicKey.from_bytes(pubkey_bytes)
            hash = @tx.sighash(@input_index, sighash_type, subscript: sub_script)
            pubkey.verify(hash, sig)
          rescue ArgumentError
            false
          end

          # Match M signatures against N public keys (standard Bitcoin CHECKMULTISIG algorithm).
          # Signatures must appear in the same order as their matching pubkeys.
          def multisig_match?(signatures, pubkeys)
            return true if signatures.empty?

            num_sigs = signatures.length
            num_keys = pubkeys.length + 1 # off-by-one compensation
            pub_idx = -1
            sig_idx = 0

            while num_sigs.positive?
              pub_idx += 1
              num_keys -= 1

              # More signatures remaining than available keys — impossible
              return false if num_sigs > num_keys

              full_sig = signatures[sig_idx]
              pubkey_bytes = pubkeys[pub_idx]

              # Empty signature — try next pubkey
              next if full_sig.empty?

              if verify_checksig(full_sig, pubkey_bytes)
                sig_idx += 1
                num_sigs -= 1
              end
            end

            true
          end

          # Validate sighash type has FORKID set and valid base type.
          def validate_sighash_type!(sighash_type)
            unless sighash_type & BSV::Transaction::Sighash::FORK_ID != 0
              raise ScriptError.new(ScriptErrorCode::INVALID_SIGHASH_TYPE, 'sighash type missing FORKID')
            end

            base = sighash_type & BSV::Transaction::Sighash::MASK
            return if [BSV::Transaction::Sighash::ALL, BSV::Transaction::Sighash::NONE,
                       BSV::Transaction::Sighash::SINGLE].include?(base)

            raise ScriptError.new(
              ScriptErrorCode::INVALID_SIGHASH_TYPE, "invalid sighash base type: 0x#{base.to_s(16)}"
            )
          end

          # Parse DER-encoded signature bytes (without sighash byte).
          # Raises ScriptError on invalid DER format.
          def parse_der_signature!(sig_bytes)
            sig = BSV::Primitives::Signature.from_der(sig_bytes)
            raise ScriptError.new(ScriptErrorCode::SIG_HIGH_S, 'signature S value is too high') unless sig.low_s?

            sig
          rescue ArgumentError => e
            raise ScriptError.new(ScriptErrorCode::SIG_DER, "invalid DER signature: #{e.message}")
          end

          # Validate public key encoding (compressed or uncompressed).
          def validate_pubkey_encoding!(bytes)
            return if bytes.bytesize == 33 && [0x02, 0x03].include?(bytes.getbyte(0))
            return if bytes.bytesize == 65 && bytes.getbyte(0) == 0x04

            raise ScriptError.new(ScriptErrorCode::PUBKEY_TYPE, 'invalid public key encoding')
          end

          # Build subscript from current script starting after last CODESEPARATOR.
          def sub_script
            chunks = @current_script.chunks[@last_code_sep..]
            Script.from_chunks(chunks || [])
          end
        end
      end
    end
  end
end
