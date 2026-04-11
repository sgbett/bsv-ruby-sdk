# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Script::Interpreter do
  def build_interpreter
    empty = BSV::Script::Script.new
    described_class.send(:new, unlock_script: empty, lock_script: empty)
  end

  def evaluate(unlock_asm, lock_asm)
    unlock = unlock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(unlock_asm)
    lock = lock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(lock_asm)
    described_class.evaluate(unlock, lock)
  end

  # Build a signed P2PKH transaction for signature verification tests
  def build_p2pkh_tx
    priv = BSV::Primitives::PrivateKey.generate
    pub = priv.public_key
    lock_script = BSV::Script::Script.p2pkh_lock(pub.hash160)

    tx = BSV::Transaction::Transaction.new
    input = BSV::Transaction::TransactionInput.new(
      prev_tx_id: "\x00" * 32,
      prev_tx_out_index: 0
    )
    input.source_locking_script = lock_script
    input.source_satoshis = 100_000
    tx.add_input(input)
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: 99_000,
                    locking_script: lock_script
                  ))
    tx.sign(0, priv)

    { tx: tx, lock_script: lock_script, private_key: priv, public_key: pub }
  end

  # Build a signed P2PK transaction
  def build_p2pk_tx
    priv = BSV::Primitives::PrivateKey.generate
    pub = priv.public_key
    lock_script = BSV::Script::Script.p2pk_lock(pub.compressed)

    tx = BSV::Transaction::Transaction.new
    input = BSV::Transaction::TransactionInput.new(
      prev_tx_id: "\x00" * 32,
      prev_tx_out_index: 0
    )
    input.source_locking_script = lock_script
    input.source_satoshis = 50_000
    tx.add_input(input)
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: 49_000,
                    locking_script: lock_script
                  ))

    # Sign: push DER sig + hashtype
    hash = tx.sighash(0)
    sig = priv.sign(hash)
    sig_bytes = sig.to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
    tx.inputs[0].unlocking_script = BSV::Script::Script.p2pk_unlock(sig_bytes)

    { tx: tx, lock_script: lock_script }
  end

  describe 'OP_RIPEMD160' do
    it 'hashes data with RIPEMD-160' do
      interp = build_interpreter
      interp.dstack.push_bytes('hello'.b)
      interp.send(:op_ripemd160)
      expect(interp.dstack.pop_bytes).to eq(BSV::Primitives::Digest.ripemd160('hello'))
    end
  end

  describe 'OP_SHA1' do
    it 'hashes data with SHA-1' do
      interp = build_interpreter
      interp.dstack.push_bytes('hello'.b)
      interp.send(:op_sha1)
      expect(interp.dstack.pop_bytes).to eq(BSV::Primitives::Digest.sha1('hello'))
    end
  end

  describe 'OP_SHA256' do
    it 'hashes data with SHA-256' do
      interp = build_interpreter
      interp.dstack.push_bytes('hello'.b)
      interp.send(:op_sha256)
      expect(interp.dstack.pop_bytes).to eq(BSV::Primitives::Digest.sha256('hello'))
    end
  end

  describe 'OP_HASH160' do
    it 'hashes data with SHA-256 then RIPEMD-160' do
      interp = build_interpreter
      interp.dstack.push_bytes('hello'.b)
      interp.send(:op_hash160)
      expect(interp.dstack.pop_bytes).to eq(BSV::Primitives::Digest.hash160('hello'))
    end
  end

  describe 'OP_HASH256' do
    it 'hashes data with double SHA-256' do
      interp = build_interpreter
      interp.dstack.push_bytes('hello'.b)
      interp.send(:op_hash256)
      expect(interp.dstack.pop_bytes).to eq(BSV::Primitives::Digest.sha256d('hello'))
    end
  end

  describe 'hash operations via ASM' do
    it 'HASH160 of OP_1 matches known preimage' do
      # Push 1, hash it, then push the known hash and compare
      data = "\x01".b
      expected = BSV::Primitives::Digest.hash160(data)
      hex = expected.unpack1('H*')
      expect(evaluate('', "OP_1 OP_HASH160 #{hex} OP_EQUAL")).to be true
    end
  end

  describe 'OP_CHECKSIG (P2PKH)' do
    it 'verifies a valid P2PKH transaction' do
      ctx = build_p2pkh_tx
      result = described_class.verify(
        tx: ctx[:tx],
        input_index: 0,
        unlock_script: ctx[:tx].inputs[0].unlocking_script,
        lock_script: ctx[:lock_script],
        satoshis: 100_000
      )
      expect(result).to be true
    end

    it 'fails with wrong public key' do
      ctx = build_p2pkh_tx
      # Replace lock script with a different key's hash
      wrong_key = BSV::Primitives::PrivateKey.generate.public_key
      wrong_lock = BSV::Script::Script.p2pkh_lock(wrong_key.hash160)

      expect do
        described_class.verify(
          tx: ctx[:tx],
          input_index: 0,
          unlock_script: ctx[:tx].inputs[0].unlocking_script,
          lock_script: wrong_lock,
          satoshis: 100_000
        )
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:equalverify_failed)
      }
    end
  end

  describe 'OP_CHECKSIG (P2PK)' do
    it 'verifies a valid P2PK transaction' do
      ctx = build_p2pk_tx
      result = described_class.verify(
        tx: ctx[:tx],
        input_index: 0,
        unlock_script: ctx[:tx].inputs[0].unlocking_script,
        lock_script: ctx[:lock_script],
        satoshis: 50_000
      )
      expect(result).to be true
    end
  end

  describe 'OP_CHECKSIG without transaction context' do
    it 'pushes false for empty signature' do
      # Empty sig + any pubkey → false (but OP_NOT flips to true)
      priv = BSV::Primitives::PrivateKey.generate
      pub_hex = priv.public_key.to_hex
      expect(evaluate('OP_0', "#{pub_hex} OP_CHECKSIG OP_NOT")).to be true
    end
  end

  describe 'OP_CHECKSIGVERIFY' do
    it 'succeeds for valid signature' do
      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key

      # Lock: <pubkey> CHECKSIGVERIFY OP_1
      lock_script = BSV::Script::Script.from_asm("#{pub.to_hex} OP_CHECKSIGVERIFY OP_1")

      tx = BSV::Transaction::Transaction.new
      input = BSV::Transaction::TransactionInput.new(prev_tx_id: "\x00" * 32, prev_tx_out_index: 0)
      input.source_locking_script = lock_script
      input.source_satoshis = 100_000
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 99_000, locking_script: lock_script))

      # Sign against this lock script
      hash = tx.sighash(0)
      sig = priv.sign(hash)
      sig_bytes = sig.to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
      unlock_script = BSV::Script::Script.from_asm(sig_bytes.unpack1('H*'))
      tx.inputs[0].unlocking_script = unlock_script

      result = described_class.verify(
        tx: tx,
        input_index: 0,
        unlock_script: unlock_script,
        lock_script: lock_script,
        satoshis: 100_000
      )
      expect(result).to be true
    end
  end

  describe 'OP_CHECKMULTISIG' do
    it 'verifies a valid 1-of-2 multisig' do
      priv1 = BSV::Primitives::PrivateKey.generate
      priv2 = BSV::Primitives::PrivateKey.generate
      pub1 = priv1.public_key
      pub2 = priv2.public_key

      lock_script = BSV::Script::Script.p2ms_lock(1,
                                                  [pub1.compressed, pub2.compressed])

      tx = BSV::Transaction::Transaction.new
      input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: "\x00" * 32, prev_tx_out_index: 0
      )
      input.source_locking_script = lock_script
      input.source_satoshis = 100_000
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 99_000, locking_script: lock_script
                    ))

      # Sign with first key
      hash = tx.sighash(0)
      sig = priv1.sign(hash)
      sig_bytes = sig.to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
      unlock_script = BSV::Script::Script.p2ms_unlock(sig_bytes)

      tx.inputs[0].unlocking_script = unlock_script

      result = described_class.verify(
        tx: tx,
        input_index: 0,
        unlock_script: unlock_script,
        lock_script: lock_script,
        satoshis: 100_000
      )
      expect(result).to be true
    end

    it 'verifies a valid 2-of-2 multisig' do
      priv1 = BSV::Primitives::PrivateKey.generate
      priv2 = BSV::Primitives::PrivateKey.generate
      pub1 = priv1.public_key
      pub2 = priv2.public_key

      lock_script = BSV::Script::Script.p2ms_lock(2,
                                                  [pub1.compressed, pub2.compressed])

      tx = BSV::Transaction::Transaction.new
      input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: "\x00" * 32, prev_tx_out_index: 0
      )
      input.source_locking_script = lock_script
      input.source_satoshis = 100_000
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 99_000, locking_script: lock_script
                    ))

      # Sign with both keys (order must match pubkey order)
      hash = tx.sighash(0)
      sig1 = priv1.sign(hash).to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
      sig2 = priv2.sign(hash).to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
      unlock_script = BSV::Script::Script.p2ms_unlock(sig1, sig2)

      tx.inputs[0].unlocking_script = unlock_script

      result = described_class.verify(
        tx: tx,
        input_index: 0,
        unlock_script: unlock_script,
        lock_script: lock_script,
        satoshis: 100_000
      )
      expect(result).to be true
    end

    it 'fails when signatures are in wrong order' do
      priv1 = BSV::Primitives::PrivateKey.generate
      priv2 = BSV::Primitives::PrivateKey.generate
      pub1 = priv1.public_key
      pub2 = priv2.public_key

      lock_script = BSV::Script::Script.p2ms_lock(2,
                                                  [pub1.compressed, pub2.compressed])

      tx = BSV::Transaction::Transaction.new
      input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: "\x00" * 32, prev_tx_out_index: 0
      )
      input.source_locking_script = lock_script
      input.source_satoshis = 100_000
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 99_000, locking_script: lock_script
                    ))

      # Sign in WRONG order (sig2 before sig1)
      hash = tx.sighash(0)
      sig1 = priv1.sign(hash).to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
      sig2 = priv2.sign(hash).to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
      unlock_script = BSV::Script::Script.p2ms_unlock(sig2, sig1)

      tx.inputs[0].unlocking_script = unlock_script

      # NULLFAIL triggers because non-empty sigs failed
      expect do
        described_class.verify(
          tx: tx,
          input_index: 0,
          unlock_script: unlock_script,
          lock_script: lock_script,
          satoshis: 100_000
        )
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:sig_nullfail)
      }
    end

    it 'raises on non-empty dummy element' do
      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key
      lock_script = BSV::Script::Script.p2ms_lock(1, [pub.compressed])

      tx = BSV::Transaction::Transaction.new
      input = BSV::Transaction::TransactionInput.new(prev_tx_id: "\x00" * 32, prev_tx_out_index: 0)
      input.source_locking_script = lock_script
      input.source_satoshis = 100_000
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 99_000, locking_script: lock_script))

      hash = tx.sighash(0)
      sig = priv.sign(hash).to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')

      # Build unlock with non-empty dummy (OP_1 instead of OP_0)
      sig_hex = sig.unpack1('H*')
      unlock_script = BSV::Script::Script.from_asm("OP_1 #{sig_hex}")
      tx.inputs[0].unlocking_script = unlock_script

      expect do
        described_class.verify(
          tx: tx,
          input_index: 0,
          unlock_script: unlock_script,
          lock_script: lock_script,
          satoshis: 100_000
        )
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:sig_nulldummy)
      }
    end
  end

  describe 'signature encoding validation' do
    it 'rejects signature missing FORKID' do
      interp = build_interpreter
      # Signature with sighash type 0x01 (ALL, no FORKID)
      fake_sig = BSV::Primitives::Signature.new(1, 1).to_der + "\x01".b
      pub = BSV::Primitives::PrivateKey.generate.public_key.compressed
      interp.dstack.push_bytes(fake_sig)
      interp.dstack.push_bytes(pub)
      interp.instance_variable_set(:@current_script, BSV::Script::Script.new)

      expect do
        interp.send(:op_checksig)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_sighash_type)
      }
    end

    it 'rejects invalid pubkey encoding' do
      interp = build_interpreter
      # Valid-looking DER sig with FORKID
      fake_sig = BSV::Primitives::Signature.new(1, 1).to_der + "\x41".b
      interp.dstack.push_bytes(fake_sig)
      interp.dstack.push_bytes("\x05#{"\x00" * 32}") # Invalid prefix
      interp.instance_variable_set(:@current_script, BSV::Script::Script.new)

      expect do
        interp.send(:op_checksig)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:pubkey_type)
      }
    end
  end

  describe 'OP_CODESEPARATOR' do
    it 'does not affect non-signature operations' do
      expect(evaluate('', 'OP_1 OP_CODESEPARATOR')).to be true
    end
  end
end
