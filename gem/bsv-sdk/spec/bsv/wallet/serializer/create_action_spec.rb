# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleDescribes

# Test data shared across create_action specs.
LOCKING_SCRIPT = ['76a9143cf53c49c322d9d811728182939aee2dca087f9888ac'].pack('H*').b
CREATE_ACTION_FULL_TXID = 'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234'
CREATE_ACTION_TXID2     = '8a552c995db3602e85bb9df911803897d1ea17ba5cdd198605d014be49db9f72'
CREATE_ACTION_TXID3     = '490c292a700c55d5e62379828d60bf6c61850fbb4d13382f52021d3796221981'
CREATE_ACTION_TXID4     = 'b95bbe3c3f3bd420048cbf57201fc6dd4e730b2e046bf170ac0b1f78de069e8e'

RSpec.describe 'BSV::Wallet::Serializer::CreateActionArgs' do
  let(:mod) { BSV::Wallet::Serializer::CreateActionArgs }

  describe 'minimal args round-trip' do
    it 'round-trips empty args' do
      bytes = mod.serialize({})
      result = mod.deserialize(bytes)
      expect(result[:description]).to eq('')
      expect(result[:inputs]).to be_nil
      expect(result[:outputs]).to be_nil
      expect(result[:options]).to be_nil
    end

    it 'round-trips description only' do
      bytes = mod.serialize(description: 'hello')
      result = mod.deserialize(bytes)
      expect(result[:description]).to eq('hello')
    end
  end

  describe 'full args round-trip' do
    let(:args) do
      {
        description: 'test transaction',
        input_beef: "\x01\x02\x03".b,
        inputs: [
          {
            outpoint: "#{CREATE_ACTION_FULL_TXID}.0",
            unlocking_script: "\xab\xcd".b,
            unlocking_script_length: 2,
            input_description: 'input 1',
            sequence_number: 1
          }
        ],
        outputs: [
          {
            locking_script: LOCKING_SCRIPT,
            satoshis: 1000,
            output_description: 'output 1',
            basket: 'basket1',
            custom_instructions: 'custom1',
            tags: %w[tag1 tag2]
          }
        ],
        lock_time: 100,
        version: 1,
        labels: %w[label1 label2],
        options: {
          sign_and_process: true,
          accept_delayed_broadcast: false,
          trust_self: :known,
          known_txids: [CREATE_ACTION_TXID2, CREATE_ACTION_TXID3],
          return_txid_only: true,
          no_send: false,
          no_send_change: ["#{CREATE_ACTION_FULL_TXID}.1"],
          send_with: [CREATE_ACTION_TXID4],
          randomize_outputs: true
        }
      }
    end

    it 'round-trips all fields' do
      bytes  = mod.serialize(args)
      result = mod.deserialize(bytes)

      expect(result[:description]).to eq('test transaction')
      expect(result[:input_beef]).to eq("\x01\x02\x03".b)
      expect(result[:inputs].length).to eq(1)
      expect(result[:inputs][0][:outpoint]).to eq("#{CREATE_ACTION_FULL_TXID}.0")
      expect(result[:inputs][0][:unlocking_script]).to eq("\xab\xcd".b)
      expect(result[:inputs][0][:sequence_number]).to eq(1)
      expect(result[:outputs].length).to eq(1)
      expect(result[:outputs][0][:satoshis]).to eq(1000)
      expect(result[:outputs][0][:basket]).to eq('basket1')
      expect(result[:outputs][0][:tags]).to eq(%w[tag1 tag2])
      expect(result[:lock_time]).to eq(100)
      expect(result[:version]).to eq(1)
      expect(result[:labels]).to eq(%w[label1 label2])
      expect(result[:options][:trust_self]).to eq(:known)
      expect(result[:options][:known_txids]).to eq([CREATE_ACTION_TXID2, CREATE_ACTION_TXID3])
      expect(result[:options][:no_send_change]).to eq(["#{CREATE_ACTION_FULL_TXID}.1"])
      expect(result[:options][:send_with]).to eq([CREATE_ACTION_TXID4])
      expect(result[:options][:randomize_outputs]).to be(true)
    end

    it 'is idempotent (serialize → deserialize → serialize)' do
      bytes1 = mod.serialize(args)
      bytes2 = mod.serialize(mod.deserialize(bytes1))
      expect(bytes1).to eq(bytes2)
    end
  end

  describe 'inputs with unlocking_script_length only (deferred signing)' do
    it 'round-trips length placeholder without script bytes' do
      args = {
        inputs: [
          {
            outpoint: "#{CREATE_ACTION_FULL_TXID}.0",
            unlocking_script_length: 107,
            input_description: 'placeholder'
          }
        ]
      }
      result = mod.deserialize(mod.serialize(args))
      expect(result[:inputs][0][:unlocking_script_length]).to eq(107)
      expect(result[:inputs][0][:unlocking_script]).to be_nil
    end
  end

  describe 'nil collections' do
    it 'nil inputs encodes as NegativeOne and round-trips to nil' do
      bytes  = mod.serialize(inputs: nil)
      result = mod.deserialize(bytes)
      expect(result[:inputs]).to be_nil
    end

    it 'nil outputs encodes as NegativeOne and round-trips to nil' do
      bytes  = mod.serialize(outputs: nil)
      result = mod.deserialize(bytes)
      expect(result[:outputs]).to be_nil
    end

    it 'nil labels encodes as NegativeOne and round-trips to nil' do
      bytes  = mod.serialize(labels: nil)
      result = mod.deserialize(bytes)
      expect(result[:labels]).to be_nil
    end
  end

  describe 'options edge cases' do
    it 'nil options is absent from result' do
      bytes  = mod.serialize({})
      result = mod.deserialize(bytes)
      expect(result[:options]).to be_nil
    end

    it 'trust_self absent when not :known' do
      bytes  = mod.serialize(options: {})
      result = mod.deserialize(bytes)
      expect(result[:options]).not_to have_key(:trust_self)
    end

    it 'randomize_outputs: false round-trips' do
      bytes  = mod.serialize(options: { randomize_outputs: false })
      result = mod.deserialize(bytes)
      expect(result[:options][:randomize_outputs]).to be(false)
    end

    it 'nil randomize_outputs is absent' do
      bytes  = mod.serialize(options: {})
      result = mod.deserialize(bytes)
      expect(result[:options]).not_to have_key(:randomize_outputs)
    end

    it 'nil no_send_change round-trips to nil/absent' do
      bytes  = mod.serialize(options: { no_send_change: nil })
      result = mod.deserialize(bytes)
      expect(result[:options]).not_to have_key(:no_send_change)
    end
  end

  describe 'lock_time: 0 distinguished from absent' do
    it 'lock_time: 0 round-trips as 0' do
      bytes  = mod.serialize(lock_time: 0)
      result = mod.deserialize(bytes)
      expect(result[:lock_time]).to eq(0)
    end

    it 'absent lock_time round-trips as nil' do
      bytes  = mod.serialize({})
      result = mod.deserialize(bytes)
      expect(result[:lock_time]).to be_nil
    end
  end

  describe 'error handling' do
    it 'raises on empty bytes' do
      expect { mod.deserialize(''.b) }.to raise_error(ArgumentError, /empty/)
    end
  end

  describe 'Go reference vector — canonical create_action scenario' do
    it 'matches byte-for-byte with Go test fixture (full args)' do
      args = {
        description: 'test transaction',
        input_beef: "\x01\x02\x03".b,
        inputs: [
          {
            outpoint: "#{CREATE_ACTION_FULL_TXID}.0",
            unlocking_script: "\xab\xcd".b,
            unlocking_script_length: 2,
            input_description: 'input 1',
            sequence_number: 1
          }
        ],
        outputs: [
          {
            locking_script: LOCKING_SCRIPT,
            satoshis: 1000,
            output_description: 'output 1',
            basket: 'basket1',
            custom_instructions: 'custom1',
            tags: %w[tag1 tag2]
          }
        ],
        lock_time: 100,
        version: 1,
        labels: %w[label1 label2],
        options: {
          sign_and_process: true,
          accept_delayed_broadcast: false,
          trust_self: :known,
          known_txids: [CREATE_ACTION_TXID2, CREATE_ACTION_TXID3],
          return_txid_only: true,
          no_send: false,
          no_send_change: ["#{CREATE_ACTION_FULL_TXID}.1"],
          send_with: [CREATE_ACTION_TXID4],
          randomize_outputs: true
        }
      }
      bytes = mod.serialize(args)
      expect(mod.deserialize(bytes)).to include(
        description: 'test transaction',
        lock_time: 100,
        version: 1
      )
      expect(bytes.bytesize).to be > 0
      round_tripped = mod.deserialize(bytes)
      expect(round_tripped[:options][:known_txids]).to eq([CREATE_ACTION_TXID2, CREATE_ACTION_TXID3])
    end
  end
end

RSpec.describe 'BSV::Wallet::Serializer::CreateActionResult' do
  let(:mod) { BSV::Wallet::Serializer::CreateActionResult }

  describe 'minimal result round-trip' do
    it 'round-trips empty result' do
      bytes  = mod.serialize({})
      result = mod.deserialize(bytes)
      expect(result).to be_a(Hash)
      expect(result[:txid]).to be_nil
    end
  end

  describe 'full result round-trip' do
    let(:result_hash) do
      {
        txid: '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        tx: "\x01\x02\x03".b,
        no_send_change: ["#{CREATE_ACTION_FULL_TXID}.0", "#{CREATE_ACTION_FULL_TXID}.1"],
        send_with_results: [
          { txid: CREATE_ACTION_TXID2, status: :unproven },
          { txid: CREATE_ACTION_TXID3, status: :sending }
        ],
        signable_transaction: { tx: "\x04\x05\x06".b, reference: 'test-ref'.b }
      }
    end

    it 'round-trips all fields' do
      bytes  = mod.serialize(result_hash)
      result = mod.deserialize(bytes)
      expect(result[:txid]).to eq(result_hash[:txid])
      expect(result[:tx]).to eq(result_hash[:tx])
      expect(result[:no_send_change]).to eq(result_hash[:no_send_change])
      expect(result[:send_with_results][0][:status]).to eq(:unproven)
      expect(result[:send_with_results][1][:status]).to eq(:sending)
      expect(result[:signable_transaction][:reference]).to eq('test-ref'.b)
    end
  end

  describe 'tx only path' do
    it 'round-trips tx without txid' do
      bytes  = mod.serialize(tx: "\x07\x08\x09".b)
      result = mod.deserialize(bytes)
      expect(result[:tx]).to eq("\x07\x08\x09".b)
      expect(result[:txid]).to be_nil
    end
  end

  describe 'signable_transaction absent' do
    it 'is absent when not provided' do
      bytes  = mod.serialize({})
      result = mod.deserialize(bytes)
      expect(result[:signable_transaction]).to be_nil
    end
  end

  describe 'error handling' do
    it 'raises on empty bytes' do
      expect { mod.deserialize(''.b) }.to raise_error(ArgumentError, /empty/)
    end

    it 'raises when first byte is non-zero (failure indicator)' do
      expect { mod.deserialize("\x01".b) }.to raise_error(ArgumentError, /failure/)
    end
  end
end

# rubocop:enable RSpec/MultipleDescribes
