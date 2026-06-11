# frozen_string_literal: true

require 'spec_helper'
require 'bsv-sdk'
require 'json'

KV_TEST_PROTOCOL_ID = [2, 'kvstore'].freeze
KV_TEST_PUBKEY_HASH = ("\x00" * 20).b

RSpec.describe 'BSV::KVStore::Interpreter' do
  def dummy_p2pkh
    BSV::Script::Script.p2pkh_lock(KV_TEST_PUBKEY_HASH)
  end

  def pushdrop_script(fields)
    BSV::Script::Script.pushdrop_lock(fields, dummy_p2pkh, lock_position: :before)
  end

  def tx_with_output(locking_script, satoshis: 1000)
    tx = BSV::Transaction::Tx.new
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: satoshis,
                    locking_script: locking_script
                  ))
    tx
  end

  def old_format_script(protocol_id: KV_TEST_PROTOCOL_ID, key: 'my-key', value: 'my-value',
                        controller: 'controller', signature: 'sig')
    pushdrop_script([JSON.generate(protocol_id).b, key.b, value.b, controller.b, signature.b])
  end

  def new_format_script(opts = {})
    protocol_id = opts.fetch(:protocol_id, KV_TEST_PROTOCOL_ID)
    key         = opts.fetch(:key,         'my-key')
    value       = opts.fetch(:value,       'my-value')
    controller  = opts.fetch(:controller,  'controller')
    tags        = opts.fetch(:tags,        '[]')
    signature   = opts.fetch(:signature,   'sig')
    pushdrop_script([JSON.generate(protocol_id).b, key.b, value.b, controller.b, tags.b, signature.b])
  end

  let(:ctx) { { key: 'my-key', protocol_id: KV_TEST_PROTOCOL_ID } }

  describe '.call' do
    context 'with missing/invalid inputs' do
      it 'returns nil when tx is nil' do
        expect(BSV::KVStore::Interpreter.call(nil, 0, ctx)).to be_nil
      end

      it 'returns nil when output_index is out of range' do
        tx = tx_with_output(old_format_script)
        expect(BSV::KVStore::Interpreter.call(tx, 5, ctx)).to be_nil
      end

      it 'returns nil when ctx is nil' do
        tx = tx_with_output(old_format_script)
        expect(BSV::KVStore::Interpreter.call(tx, 0, nil)).to be_nil
      end

      it 'returns nil when ctx[:key] is nil' do
        tx = tx_with_output(old_format_script)
        ctx_no_key = { key: nil, protocol_id: KV_TEST_PROTOCOL_ID }
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx_no_key)).to be_nil
      end

      it 'returns nil when locking_script is nil' do
        tx = BSV::Transaction::Tx.new
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 0, locking_script: nil))
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to be_nil
      end

      it 'returns nil for a non-PushDrop locking script' do
        tx = tx_with_output(dummy_p2pkh)
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to be_nil
      end
    end

    context 'with old format (5 fields)' do
      it 'returns the value when key and protocol_id match' do
        tx = tx_with_output(old_format_script)
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to eq('my-value')
      end

      it 'returns an empty string when value field is empty' do
        tx = tx_with_output(old_format_script(value: ''))
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to eq('')
      end

      it 'returns the value at the correct output index' do
        tx = BSV::Transaction::Tx.new
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 0, locking_script: dummy_p2pkh))
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 1000, locking_script: old_format_script))
        expect(BSV::KVStore::Interpreter.call(tx, 1, ctx)).to eq('my-value')
      end

      it 'returns nil for a non-matching output index when tx has multiple outputs' do
        tx = BSV::Transaction::Tx.new
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 0, locking_script: dummy_p2pkh))
        tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: 1000, locking_script: old_format_script))
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to be_nil
      end
    end

    context 'with new format (6 fields)' do
      it 'returns the value when key and protocol_id match' do
        tx = tx_with_output(new_format_script)
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to eq('my-value')
      end

      it 'returns an empty string when value field is empty' do
        tx = tx_with_output(new_format_script(value: ''))
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to eq('')
      end
    end

    context 'when key mismatches' do
      it 'returns nil when the stored key does not match ctx[:key] (old format)' do
        tx = tx_with_output(old_format_script(key: 'other-key'))
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to be_nil
      end

      it 'returns nil when the stored key does not match ctx[:key] (new format)' do
        tx = tx_with_output(new_format_script(key: 'other-key'))
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to be_nil
      end
    end

    context 'when protocol_id mismatches' do
      it 'returns nil when stored protocol_id differs (old format)' do
        tx = tx_with_output(old_format_script(protocol_id: [1, 'other-protocol']))
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to be_nil
      end

      it 'returns nil when stored protocol_id differs (new format)' do
        tx = tx_with_output(new_format_script(protocol_id: [1, 'other-protocol']))
        expect(BSV::KVStore::Interpreter.call(tx, 0, ctx)).to be_nil
      end

      it 'matches compact JSON protocol_id via array equality' do
        script = pushdrop_script(['[2,"kvstore"]'.b, 'my-key'.b, 'my-value'.b, 'ctrl'.b, 'sig'.b])
        expect(BSV::KVStore::Interpreter.call(tx_with_output(script), 0, ctx)).to eq('my-value')
      end

      it 'matches spaced JSON protocol_id via array equality' do
        script = pushdrop_script(['[ 2, "kvstore" ]'.b, 'my-key'.b, 'my-value'.b, 'ctrl'.b, 'sig'.b])
        expect(BSV::KVStore::Interpreter.call(tx_with_output(script), 0, ctx)).to eq('my-value')
      end
    end

    context 'with malformed JSON in protocol_id field' do
      it 'returns nil' do
        bad_script = pushdrop_script(['not-json'.b, 'my-key'.b, 'my-value'.b, 'ctrl'.b, 'sig'.b])
        expect(BSV::KVStore::Interpreter.call(tx_with_output(bad_script), 0, ctx)).to be_nil
      end
    end

    context 'with wrong field count' do
      it 'returns nil when script has fewer than 5 fields' do
        bad_script = pushdrop_script([JSON.generate(KV_TEST_PROTOCOL_ID).b, 'my-key'.b, 'my-value'.b])
        expect(BSV::KVStore::Interpreter.call(tx_with_output(bad_script), 0, ctx)).to be_nil
      end

      it 'returns nil when script has more than 6 fields' do
        pid = JSON.generate(KV_TEST_PROTOCOL_ID).b
        bad_script = pushdrop_script([pid, 'my-key'.b, 'my-value'.b, 'ctrl'.b, 'tags'.b, 'sig'.b, 'extra'.b])
        expect(BSV::KVStore::Interpreter.call(tx_with_output(bad_script), 0, ctx)).to be_nil
      end
    end
  end
end
