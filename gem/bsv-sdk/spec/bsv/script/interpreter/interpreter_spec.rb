# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Script::Interpreter do
  def evaluate(unlock_asm, lock_asm)
    unlock = unlock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(unlock_asm)
    lock = lock_asm.empty? ? BSV::Script::Script.new : BSV::Script::Script.from_asm(lock_asm)
    described_class.evaluate(unlock, lock)
  end

  # Build a signed P2PKH transaction
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

    hash = tx.sighash(0)
    sig = priv.sign(hash)
    sig_bytes = sig.to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
    tx.inputs[0].unlocking_script = BSV::Script::Script.p2pk_unlock(sig_bytes)

    { tx: tx, lock_script: lock_script }
  end

  # Build a signed 2-of-3 multisig transaction
  def build_multisig_tx
    keys = Array.new(3) { BSV::Primitives::PrivateKey.generate }
    pubkeys = keys.map { |k| k.public_key.compressed }
    lock_script = BSV::Script::Script.p2ms_lock(2, pubkeys)

    tx = BSV::Transaction::Transaction.new
    input = BSV::Transaction::TransactionInput.new(
      prev_tx_id: "\x00" * 32,
      prev_tx_out_index: 0
    )
    input.source_locking_script = lock_script
    input.source_satoshis = 200_000
    tx.add_input(input)
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: 199_000,
                    locking_script: lock_script
                  ))

    # Sign with keys 0 and 1 (in order)
    hash = tx.sighash(0)
    sig0 = keys[0].sign(hash).to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
    sig1 = keys[1].sign(hash).to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
    tx.inputs[0].unlocking_script = BSV::Script::Script.p2ms_unlock(sig0, sig1)

    { tx: tx, lock_script: lock_script, keys: keys }
  end

  describe '.evaluate' do
    it 'returns true for simple truthy script' do
      expect(evaluate('', 'OP_1')).to be true
    end

    it 'executes unlock then lock script sequentially' do
      expect(evaluate('OP_1 OP_2', 'OP_DROP')).to be true
    end

    it 'carries data stack from unlock to lock' do
      expect(evaluate('deadbeef', 'OP_DUP OP_DROP')).to be true
    end

    it 'raises EMPTY_STACK when both scripts are empty' do
      expect do
        evaluate('', '')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:empty_stack)
      }
    end

    it 'raises EVAL_FALSE when top of stack is falsy' do
      expect do
        evaluate('', 'OP_0')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end

    it 'raises INVALID_OPCODE for unhandled opcodes' do
      expect do
        evaluate('', 'OP_1 OP_INVALIDOPCODE')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_opcode)
      }
    end

    it 'clears alt stack between scripts' do
      expect do
        evaluate('OP_1 OP_TOALTSTACK', 'OP_FROMALTSTACK')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:invalid_stack_operation)
      }
    end

    it 'only checks top of final stack for truthiness' do
      expect(evaluate('OP_0 OP_0 OP_0', 'OP_1')).to be true
    end
  end

  describe 'P2PKH end-to-end' do
    it 'verifies a valid P2PKH transaction via Interpreter.verify' do
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

    it 'fails with wrong public key (EQUALVERIFY)' do
      ctx = build_p2pkh_tx
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

  describe 'P2PK end-to-end' do
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

  describe 'multisig end-to-end' do
    it 'verifies a valid 2-of-3 multisig transaction' do
      ctx = build_multisig_tx
      result = described_class.verify(
        tx: ctx[:tx],
        input_index: 0,
        unlock_script: ctx[:tx].inputs[0].unlocking_script,
        lock_script: ctx[:lock_script],
        satoshis: 200_000
      )
      expect(result).to be true
    end
  end

  describe 'Transaction#verify_input' do
    it 'verifies a P2PKH input' do
      ctx = build_p2pkh_tx
      expect(ctx[:tx].verify_input(0)).to be true
    end

    it 'verifies a P2PK input' do
      ctx = build_p2pk_tx
      expect(ctx[:tx].verify_input(0)).to be true
    end

    it 'verifies a multisig input' do
      ctx = build_multisig_tx
      expect(ctx[:tx].verify_input(0)).to be true
    end

    it 'fails with wrong locking script' do
      ctx = build_p2pkh_tx
      wrong_key = BSV::Primitives::PrivateKey.generate.public_key
      ctx[:tx].inputs[0].source_locking_script = BSV::Script::Script.p2pkh_lock(wrong_key.hash160)

      expect do
        ctx[:tx].verify_input(0)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:equalverify_failed)
      }
    end

    it 'fails with corrupted signature' do
      ctx = build_p2pkh_tx
      # Corrupt the unlocking script by flipping a byte in the signature
      original = ctx[:tx].inputs[0].unlocking_script.to_binary.dup
      # Flip a byte in the middle of the signature (avoiding length prefix)
      original.setbyte(5, original.getbyte(5) ^ 0xff)
      ctx[:tx].inputs[0].unlocking_script = BSV::Script::Script.from_binary(original)

      expect do
        ctx[:tx].verify_input(0)
      end.to raise_error(BSV::Script::ScriptError)
    end
  end

  describe 'OP_RETURN scripts' do
    it 'evaluates OP_RETURN as early success (after genesis)' do
      expect(evaluate('OP_1', 'OP_RETURN')).to be true
    end

    it 'succeeds with data after OP_RETURN' do
      expect(evaluate('OP_1', 'OP_RETURN deadbeef')).to be true
    end

    it 'fails when stack is empty before OP_RETURN' do
      expect do
        evaluate('', 'OP_RETURN')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:empty_stack)
      }
    end
  end

  describe 'conditional scripts with CHECKSIG' do
    it 'takes true branch with valid signature' do
      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key

      # Lock: OP_IF <pubkey> OP_CHECKSIG OP_ELSE OP_0 OP_ENDIF
      lock_script = BSV::Script::Script.from_asm(
        "OP_IF #{pub.to_hex} OP_CHECKSIG OP_ELSE OP_0 OP_ENDIF"
      )

      tx = BSV::Transaction::Transaction.new
      input = BSV::Transaction::TransactionInput.new(prev_tx_id: "\x00" * 32, prev_tx_out_index: 0)
      input.source_locking_script = lock_script
      input.source_satoshis = 100_000
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 99_000, locking_script: lock_script))

      hash = tx.sighash(0)
      sig = priv.sign(hash)
      sig_bytes = sig.to_der + [BSV::Transaction::Sighash::ALL_FORK_ID].pack('C')
      # Unlock: <sig> OP_1 (OP_1 selects the true branch)
      unlock_script = BSV::Script::Script.from_asm("#{sig_bytes.unpack1('H*')} OP_1")
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

    it 'takes false branch and fails' do
      priv = BSV::Primitives::PrivateKey.generate
      pub = priv.public_key

      # Lock: OP_IF <pubkey> OP_CHECKSIG OP_ELSE OP_0 OP_ENDIF
      lock_script = BSV::Script::Script.from_asm(
        "OP_IF #{pub.to_hex} OP_CHECKSIG OP_ELSE OP_0 OP_ENDIF"
      )

      tx = BSV::Transaction::Transaction.new
      input = BSV::Transaction::TransactionInput.new(prev_tx_id: "\x00" * 32, prev_tx_out_index: 0)
      input.source_locking_script = lock_script
      input.source_satoshis = 100_000
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 99_000, locking_script: lock_script))
      tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_0')

      expect do
        described_class.verify(
          tx: tx,
          input_index: 0,
          unlock_script: tx.inputs[0].unlocking_script,
          lock_script: lock_script,
          satoshis: 100_000
        )
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
      }
    end
  end

  describe 'error messages' do
    it 'includes a meaningful message with error code' do
      expect do
        evaluate('', 'OP_0')
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:eval_false)
        expect(e.message).to include('false')
      }
    end

    it 'ScriptError is a StandardError' do
      expect(BSV::Script::ScriptError.new(:test)).to be_a(StandardError)
    end
  end

  describe 'nonstandard scripts' do
    it 'evaluates a hash-puzzle lock script' do
      secret = 'my_secret'.b
      hash = BSV::Primitives::Digest.sha256(secret)
      hex = hash.unpack1('H*')
      expect(evaluate(secret.unpack1('H*'), "OP_SHA256 #{hex} OP_EQUAL")).to be true
    end

    it 'evaluates arithmetic-based lock script' do
      # Unlock pushes 3 and 4, lock adds and checks sum equals 7
      expect(evaluate('OP_3 OP_4', 'OP_ADD OP_7 OP_EQUAL')).to be true
    end
  end

  describe 'FORKID enforcement' do
    it 'rejects signatures without FORKID in sighash type' do
      result = build_p2pkh_tx
      tx = result[:tx]
      lock_script = result[:lock_script]

      # Tamper with the signature's sighash byte: replace FORKID (0x41) with non-FORKID (0x01)
      unlock_script = tx.inputs[0].unlocking_script
      sig_chunk = unlock_script.chunks[0]
      tampered_sig = sig_chunk.data.dup
      tampered_sig[-1] = "\x01".b # ALL without FORKID
      tampered_unlock = BSV::Script::Script.builder
                                           .push_data(tampered_sig)
                                           .push_data(unlock_script.chunks[1].data)
                                           .build

      expect do
        described_class.verify(tx: tx, input_index: 0, unlock_script: tampered_unlock,
                               lock_script: lock_script, satoshis: 100_000)
      end.to raise_error(BSV::Script::ScriptError, /FORKID/)
    end
  end
end
