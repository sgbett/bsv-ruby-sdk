# frozen_string_literal: true

require 'spec_helper'
require 'bsv-sdk'
require 'json'

GLOBAL_TEST_PROTOCOL_ID = [1, 'kvstore'].freeze
GLOBAL_TEST_PUBKEY_HASH = ("\x00" * 20).b

RSpec.describe BSV::KVStore::Global do
  # ---- Helpers ----

  def dummy_p2pkh
    BSV::Script::Script.p2pkh_lock(GLOBAL_TEST_PUBKEY_HASH)
  end

  def pushdrop_script(fields)
    BSV::Script::Script.pushdrop_lock(fields, dummy_p2pkh, lock_position: :before)
  end

  # Build a raw old-format PushDrop script (5 fields: no real signature)
  def raw_old_format_script(protocol_id: GLOBAL_TEST_PROTOCOL_ID, key: 'my-key',
                            value: 'hello', controller_hex: ('aa' * 33),
                            signature: 'fake-sig')
    pushdrop_script([
                      JSON.generate(protocol_id).b,
                      key.b,
                      value.b,
                      [controller_hex].pack('H*').b,
                      signature.b
                    ])
  end

  # Build a raw new-format PushDrop script (6 fields: with tags, no real signature)
  def raw_new_format_script(protocol_id: GLOBAL_TEST_PROTOCOL_ID, key: 'my-key',
                            value: 'hello', controller_hex: ('aa' * 33),
                            tags: ['tag1'], signature: 'fake-sig')
    pushdrop_script([
                      JSON.generate(protocol_id).b,
                      key.b,
                      value.b,
                      [controller_hex].pack('H*').b,
                      JSON.generate(tags).b,
                      signature.b
                    ])
  end

  # Create a minimal BEEF wrapping a single tx with the given locking script
  def beef_with_script(locking_script, satoshis: 1000)
    tx = BSV::Transaction::Tx.new
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: satoshis,
                    locking_script: locking_script
                  ))
    beef = BSV::Transaction::Beef.new
    beef.transactions << BSV::Transaction::Beef::RawTxEntry.new(transaction: tx)
    beef.to_binary
  end

  # Build a synthetic output hash as the overlay would return it
  def overlay_output(locking_script:, satoshis: 1000, output_index: 0)
    {
      'beef' => beef_with_script(locking_script, satoshis: satoshis),
      'outputIndex' => output_index
    }
  end

  def lookup_answer(outputs)
    BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: outputs)
  end

  def empty_answer
    BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: [])
  end

  # ---- Shared setup ----

  let(:resolver) { instance_double(BSV::Overlay::LookupResolver) }
  let(:proto_wallet) { instance_double(BSV::Wallet::ProtoWallet) }
  let(:global) { described_class.new(lookup_resolver: resolver, proto_wallet: proto_wallet) }

  # ---- #get: selector validation ----

  describe '#get' do
    context 'with no selector' do
      it 'raises ArgumentError when query is empty' do
        expect { global.get({}) }.to raise_error(ArgumentError, /selector/)
      end

      it 'raises ArgumentError when key is an empty string' do
        expect { global.get({ key: '' }) }.to raise_error(ArgumentError, /selector/)
      end

      it 'raises ArgumentError when controller is an empty string' do
        expect { global.get({ controller: '' }) }.to raise_error(ArgumentError, /selector/)
      end

      it 'raises ArgumentError when protocol_id has wrong arity' do
        expect { global.get({ protocol_id: [1] }) }.to raise_error(ArgumentError, /selector/)
      end

      it 'raises ArgumentError when tags is an empty array' do
        expect { global.get({ tags: [] }) }.to raise_error(ArgumentError, /selector/)
      end
    end

    context 'with only key' do
      let(:controller_hex) { 'aa' * 33 }
      let(:key)            { 'my-key' }
      let(:value)          { 'my-value' }

      before do
        allow(proto_wallet).to receive(:verify_signature).and_return({ valid: true })
        allow(resolver).to receive(:query).and_return(
          lookup_answer([
                          overlay_output(locking_script: raw_old_format_script(
                            key: key, value: value, controller_hex: controller_hex
                          ))
                        ])
        )
      end

      it 'issues a query to the resolver with the key' do
        captured = nil
        allow(resolver).to receive(:query) { |q|
          captured = q
          empty_answer
        }
        global.get({ key: key })
        expect(captured.service).to eq('ls_kvstore')
        expect(captured.query[:key]).to eq(key)
      end

      it 'returns an array of matching entries' do
        entries = global.get({ key: key })
        expect(entries).to be_an(Array)
        expect(entries.length).to eq(1)
        expect(entries.first.key).to eq(key)
        expect(entries.first.value).to eq(value)
      end
    end

    context 'with key + controller' do
      let(:controller_hex) { 'bb' * 33 }

      before do
        allow(proto_wallet).to receive(:verify_signature).and_return({ valid: true })
        allow(resolver).to receive(:query).and_return(
          lookup_answer([
                          overlay_output(locking_script: raw_old_format_script(
                            key: 'k', value: 'v', controller_hex: controller_hex
                          ))
                        ])
        )
      end

      it 'returns an Array (not a single entry)' do
        result = global.get({ key: 'k', controller: controller_hex })
        expect(result).to be_an(Array)
        expect(result.length).to eq(1)
      end

      it 'returns empty Array when resolver returns no outputs' do
        allow(resolver).to receive(:query).and_return(empty_answer)
        result = global.get({ key: 'k', controller: controller_hex })
        expect(result).to eq([])
      end
    end

    context 'when resolver returns no outputs' do
      before do
        allow(resolver).to receive(:query).and_return(empty_answer)
      end

      it 'returns an empty array' do
        expect(global.get({ key: 'k' })).to eq([])
      end
    end

    context 'when resolver returns a non-output-list answer' do
      before do
        allow(resolver).to receive(:query).and_return(
          BSV::Overlay::LookupAnswer.new(type: 'freeform', outputs: [])
        )
      end

      it 'returns an empty array' do
        expect(global.get({ key: 'k' })).to eq([])
      end
    end

    context 'with malformed BEEF on one output' do
      before do
        bad_output  = { 'beef' => 'not-valid-beef', 'outputIndex' => 0 }
        good_script = raw_old_format_script
        good_output = overlay_output(locking_script: good_script)
        allow(proto_wallet).to receive(:verify_signature).and_return({ valid: true })
        allow(resolver).to receive(:query).and_return(
          lookup_answer([bad_output, good_output])
        )
      end

      it 'silently skips the malformed output and returns the good one' do
        entries = global.get({ key: 'my-key' })
        expect(entries.length).to eq(1)
        expect(entries.first.key).to eq('my-key')
      end
    end

    context 'with a negative outputIndex (untrusted overlay response)' do
      before do
        good_script   = raw_old_format_script
        good_output   = overlay_output(locking_script: good_script)
        negative      = good_output.merge('outputIndex' => -1)
        allow(proto_wallet).to receive(:verify_signature).and_return({ valid: true })
        allow(resolver).to receive(:query).and_return(
          lookup_answer([negative, good_output])
        )
      end

      it 'silently skips the entry rather than reading the wrong output via negative indexing' do
        entries = global.get({ key: 'my-key' })
        expect(entries.length).to eq(1)
        expect(entries.first.key).to eq('my-key')
      end
    end

    context 'with signature verification failing on one output' do
      let(:good_script) { raw_old_format_script(key: 'good') }
      let(:bad_script)  { raw_old_format_script(key: 'bad') }

      before do
        allow(resolver).to receive(:query).and_return(
          lookup_answer([
                          overlay_output(locking_script: bad_script),
                          overlay_output(locking_script: good_script)
                        ])
        )

        call_count = 0
        allow(proto_wallet).to receive(:verify_signature) do
          call_count += 1
          raise BSV::Wallet::InvalidSignatureError if call_count == 1

          { valid: true }
        end
      end

      it 'skips the output with failed verification' do
        entries = global.get({ key: 'good' })
        expect(entries.length).to eq(1)
        expect(entries.first.key).to eq('good')
      end
    end

    context 'with include_token: true' do
      let(:satoshis) { 5000 }

      before do
        allow(proto_wallet).to receive(:verify_signature).and_return({ valid: true })
        allow(resolver).to receive(:query).and_return(
          lookup_answer([
                          overlay_output(
                            locking_script: raw_old_format_script,
                            satoshis: satoshis
                          )
                        ])
        )
      end

      it 'populates the token field on each entry' do
        entries = global.get({ key: 'my-key' }, include_token: true)
        expect(entries.length).to eq(1)
        token = entries.first.token
        expect(token).to be_a(BSV::KVStore::Token)
        expect(token.output_index).to eq(0)
        expect(token.satoshis).to eq(satoshis)
        expect(token.dtxid).to be_a(String)
        expect(token.dtxid.length).to eq(64)
        expect(token.beef).to be_a(BSV::Transaction::Beef)
      end

      it 'does not populate token when include_token is false (default)' do
        entries = global.get({ key: 'my-key' })
        expect(entries.first.token).to be_nil
      end
    end

    context 'with history: true' do
      before do
        allow(proto_wallet).to receive(:verify_signature).and_return({ valid: true })
        allow_any_instance_of(BSV::Overlay::Historian).to receive(:build_history).and_return(['old-value']) # rubocop:disable RSpec/AnyInstance
        allow(resolver).to receive(:query).and_return(
          lookup_answer([overlay_output(locking_script: raw_old_format_script)])
        )
      end

      it 'populates the history field via Historian' do
        entries = global.get({ key: 'my-key' }, history: true)
        expect(entries.length).to eq(1)
        expect(entries.first.history).to eq(['old-value'])
      end

      it 'does not populate history when history is false (default)' do
        allow_any_instance_of(BSV::Overlay::Historian).to receive(:build_history).and_call_original # rubocop:disable RSpec/AnyInstance
        entries = global.get({ key: 'my-key' })
        expect(entries.first.history).to be_nil
      end
    end

    context 'with old 5-field format' do
      let(:controller_hex) { 'cc' * 33 }

      before do
        allow(proto_wallet).to receive(:verify_signature).and_return({ valid: true })
        allow(resolver).to receive(:query).and_return(
          lookup_answer([
                          overlay_output(locking_script: raw_old_format_script(
                            key: 'k1', value: 'v1', controller_hex: controller_hex
                          ))
                        ])
        )
      end

      it 'decodes key, value, controller correctly' do
        entries = global.get({ key: 'k1' })
        expect(entries.length).to eq(1)
        entry = entries.first
        expect(entry.key).to eq('k1')
        expect(entry.value).to eq('v1')
        expect(entry.controller).to eq(controller_hex)
        expect(entry.tags).to be_nil
        expect(entry.protocol_id).to eq(GLOBAL_TEST_PROTOCOL_ID)
      end
    end

    context 'with new 6-field format' do
      let(:controller_hex) { 'dd' * 33 }
      let(:tags) { %w[alpha beta] }

      before do
        allow(proto_wallet).to receive(:verify_signature).and_return({ valid: true })
        allow(resolver).to receive(:query).and_return(
          lookup_answer([
                          overlay_output(locking_script: raw_new_format_script(
                            key: 'k2', value: 'v2', controller_hex: controller_hex, tags: tags
                          ))
                        ])
        )
      end

      it 'decodes key, value, controller, and tags correctly' do
        entries = global.get({ key: 'k2' })
        expect(entries.length).to eq(1)
        entry = entries.first
        expect(entry.key).to eq('k2')
        expect(entry.value).to eq('v2')
        expect(entry.controller).to eq(controller_hex)
        expect(entry.tags).to eq(tags)
      end
    end

    context 'with a script having wrong field count' do
      before do
        # 4 fields — neither 5 nor 6
        bad_script = pushdrop_script([
                                       JSON.generate(GLOBAL_TEST_PROTOCOL_ID).b,
                                       'key'.b,
                                       'value'.b,
                                       'sig'.b
                                     ])
        allow(resolver).to receive(:query).and_return(
          lookup_answer([overlay_output(locking_script: bad_script)])
        )
      end

      it 'silently skips the output and returns empty array' do
        expect(global.get({ key: 'key' })).to eq([])
      end
    end

    context 'when camelising query keys' do
      before do
        allow(proto_wallet).to receive(:verify_signature).and_return({ valid: true })
        allow(resolver).to receive(:query).and_return(empty_answer)
      end

      it 'converts protocol_id to protocolID in the query' do
        captured = nil
        allow(resolver).to receive(:query) { |q|
          captured = q
          empty_answer
        }
        global.get({ protocol_id: GLOBAL_TEST_PROTOCOL_ID })
        expect(captured.query[:protocolID]).to eq(GLOBAL_TEST_PROTOCOL_ID)
        expect(captured.query.key?(:protocol_id)).to be(false)
      end

      it 'converts tag_query_mode to tagQueryMode in the query' do
        captured = nil
        allow(resolver).to receive(:query) { |q|
          captured = q
          empty_answer
        }
        global.get({ tags: ['t'], tag_query_mode: 'all' })
        expect(captured.query[:tagQueryMode]).to eq('all')
        expect(captured.query.key?(:tag_query_mode)).to be(false)
      end
    end

    context 'with default resolver construction' do
      it 'instantiates without error when no resolver is supplied' do
        expect { described_class.new(network_preset: :local) }.not_to raise_error
      end
    end
  end
end
