# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'BSV::X402::NonceProvider' do
  describe BSV::X402::NonceProvider do
    it 'raises NotImplementedError when reserve_nonce is called on an includer without override' do
      klass = Class.new { include BSV::X402::NonceProvider }
      expect { klass.new.reserve_nonce }.to raise_error(NotImplementedError, /reserve_nonce/)
    end

    it 'can be included in a class that overrides reserve_nonce' do
      nonce_utxo = BSV::X402::NonceUTXO.new(
        txid: 'aa' * 32, vout: 0, satoshis: 1, locking_script_hex: '00'
      )

      klass = Class.new do
        include BSV::X402::NonceProvider

        def reserve_nonce
          BSV::X402::NonceUTXO.new(
            txid: 'aa' * 32, vout: 0, satoshis: 1, locking_script_hex: '00'
          )
        end
      end

      result = klass.new.reserve_nonce
      expect(result).to be_a(BSV::X402::NonceUTXO)
      expect(result.txid).to eq(nonce_utxo.txid)
    end
  end

  describe BSV::X402::StaticNonceProvider do
    subject(:provider) { described_class.new(nonce_utxo) }

    let(:nonce_utxo) do
      BSV::X402::NonceUTXO.new(
        txid: 'bb' * 32,
        vout: 1,
        satoshis: 5,
        locking_script_hex: "76a914#{'aa' * 20}88ac"
      )
    end

    it 'returns the fixed nonce UTXO' do
      expect(provider.reserve_nonce).to be(nonce_utxo)
    end

    it 'returns the same UTXO on every call' do
      first  = provider.reserve_nonce
      second = provider.reserve_nonce
      expect(first).to be(second)
    end

    it 'includes NonceProvider' do
      expect(described_class.ancestors).to include(BSV::X402::NonceProvider)
    end
  end
end
