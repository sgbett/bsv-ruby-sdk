# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleDescribes

SENDER_PUBKEY_HEX = "02#{'11' * 32}".freeze

RSpec.describe 'BSV::Wallet::Serializer::InternalizeActionArgs' do
  let(:mod) { BSV::Wallet::Serializer::InternalizeActionArgs }

  describe 'wallet_payment output round-trip' do
    let(:args) do
      {
        tx: "\x01\x02\x03\x04".b,
        outputs: [
          {
            output_index: 0,
            protocol: :wallet_payment,
            payment_remittance: {
              sender_identity_key: SENDER_PUBKEY_HEX,
              derivation_prefix: 'prefix'.b,
              derivation_suffix: 'suffix'.b
            }
          }
        ],
        description: 'test'
      }
    end

    it 'round-trips wallet_payment output' do
      bytes  = mod.serialize(args)
      result = mod.deserialize(bytes)
      expect(result[:outputs][0][:protocol]).to eq(:wallet_payment)
      expect(result[:outputs][0][:payment_remittance][:sender_identity_key]).to eq(SENDER_PUBKEY_HEX)
      expect(result[:outputs][0][:payment_remittance][:derivation_prefix]).to eq('prefix'.b)
      expect(result[:outputs][0][:payment_remittance][:derivation_suffix]).to eq('suffix'.b)
    end
  end

  describe 'basket_insertion output round-trip' do
    let(:args) do
      {
        tx: "\x01".b,
        outputs: [
          {
            output_index: 1,
            protocol: :basket_insertion,
            insertion_remittance: {
              basket: 'test-basket',
              custom_instructions: 'instructions',
              tags: %w[tag1 tag2]
            }
          }
        ],
        description: 'minimal'
      }
    end

    it 'round-trips basket_insertion output' do
      bytes  = mod.serialize(args)
      result = mod.deserialize(bytes)
      expect(result[:outputs][0][:protocol]).to eq(:basket_insertion)
      expect(result[:outputs][0][:insertion_remittance][:basket]).to eq('test-basket')
      expect(result[:outputs][0][:insertion_remittance][:custom_instructions]).to eq('instructions')
      expect(result[:outputs][0][:insertion_remittance][:tags]).to eq(%w[tag1 tag2])
    end
  end

  describe 'mixed outputs round-trip' do
    let(:args) do
      {
        tx: "\x01\x02\x03\x04".b,
        outputs: [
          {
            output_index: 0,
            protocol: :wallet_payment,
            payment_remittance: {
              sender_identity_key: SENDER_PUBKEY_HEX,
              derivation_prefix: 'prefix'.b,
              derivation_suffix: 'suffix'.b
            }
          },
          {
            output_index: 1,
            protocol: :basket_insertion,
            insertion_remittance: {
              basket: 'test-basket',
              custom_instructions: 'instructions',
              tags: %w[tag1 tag2]
            }
          }
        ],
        description: 'test description',
        labels: %w[label1 label2],
        seek_permission: true
      }
    end

    it 'round-trips all fields including mixed protocols' do
      bytes  = mod.serialize(args)
      result = mod.deserialize(bytes)
      expect(result[:tx]).to eq("\x01\x02\x03\x04".b)
      expect(result[:outputs].length).to eq(2)
      expect(result[:outputs][0][:protocol]).to eq(:wallet_payment)
      expect(result[:outputs][1][:protocol]).to eq(:basket_insertion)
      expect(result[:description]).to eq('test description')
      expect(result[:labels]).to eq(%w[label1 label2])
      expect(result[:seek_permission]).to be(true)
    end
  end

  describe 'empty outputs' do
    it 'round-trips empty outputs array' do
      args   = { tx: "\x01".b, outputs: [], description: 'empty' }
      result = mod.deserialize(mod.serialize(args))
      expect(result[:outputs]).to eq([])
    end
  end

  describe 'seek_permission nil' do
    it 'absent seek_permission round-trips as nil/absent' do
      args   = { tx: "\x01".b, outputs: [], description: 'test' }
      result = mod.deserialize(mod.serialize(args))
      expect(result[:seek_permission]).to be_nil
    end
  end

  describe 'invalid protocol' do
    it 'raises on unknown protocol byte when deserialising' do
      args = { tx: "\x01".b, outputs: [], description: 'test' }
      mod.serialize(args)

      bad_bytes = inject_bad_protocol_byte(args)
      expect { mod.deserialize(bad_bytes) }.to raise_error(ArgumentError, /protocol/)
    end

    def inject_bad_protocol_byte(args)
      w = BSV::Wallet::Wire::Writer.new
      tx = args[:tx].b
      w.write_varint(tx.bytesize)
      w.write_bytes(tx)
      w.write_varint(1) # 1 output
      w.write_varint(0) # output_index 0
      w.write_byte(99)  # invalid protocol byte
      w.buf
    end
  end
end

RSpec.describe 'BSV::Wallet::Serializer::InternalizeActionResult' do
  let(:mod) { BSV::Wallet::Serializer::InternalizeActionResult }

  it 'serialises to empty bytes' do
    expect(mod.serialize({})).to eq(''.b)
  end

  it 'deserialises any bytes to { accepted: true }' do
    expect(mod.deserialize('')).to eq({ accepted: true })
    expect(mod.deserialize(nil)).to eq({ accepted: true })
  end
end

# rubocop:enable RSpec/MultipleDescribes
