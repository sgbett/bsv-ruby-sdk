# frozen_string_literal: true

RSpec.describe 'BSV::Wallet::Serializer::RevealCounterpartyKeyLinkage' do
  subject(:mod) { BSV::Wallet::Serializer::RevealCounterpartyKeyLinkage }

  let(:counterparty_hex) { '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798' }
  let(:verifier_hex)     { '02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5' }
  let(:prover_hex)       { '02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9' }
  let(:counterparty_bin) { [counterparty_hex].pack('H*') }
  let(:verifier_bin)     { [verifier_hex].pack('H*') }
  let(:prover_bin)       { [prover_hex].pack('H*') }

  describe 'Args' do
    it 'round-trips binary pubkeys' do
      args = { counterparty: counterparty_bin, verifier: verifier_bin }
      bytes = mod::Args.serialize(args)
      back = mod::Args.deserialize(bytes)
      expect(back[:counterparty]).to eq(counterparty_bin)
      expect(back[:verifier]).to eq(verifier_bin)
    end

    it 'accepts hex pubkeys' do
      args = { counterparty: counterparty_hex, verifier: verifier_hex }
      bytes = mod::Args.serialize(args)
      back = mod::Args.deserialize(bytes)
      expect(back[:counterparty]).to eq(counterparty_bin)
      expect(back[:verifier]).to eq(verifier_bin)
    end

    it 'round-trips privileged params' do
      args = { counterparty: counterparty_bin, verifier: verifier_bin, privileged: true, privileged_reason: 'r' }
      back = mod::Args.deserialize(mod::Args.serialize(args))
      expect(back[:privileged]).to be(true)
      expect(back[:privileged_reason]).to eq('r')
    end

    it 'raises WERR_INVALID_PARAMETER when counterparty missing' do
      expect { mod::Args.serialize({ verifier: verifier_bin }) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises WERR_INVALID_PARAMETER when verifier missing' do
      expect { mod::Args.serialize({ counterparty: counterparty_bin }) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe 'Result' do
    let(:full_result) do
      {
        prover: prover_bin,
        verifier: verifier_bin,
        counterparty: counterparty_bin,
        revelation_time: '2024-01-01T00:00:00Z',
        encrypted_linkage: "\xAB\xCD".b,
        encrypted_linkage_proof: "\xEF".b
      }
    end

    it 'round-trips the full result with hex pubkey fields (ADR-001)' do
      bytes = mod::Result.serialize(full_result)
      back = mod::Result.deserialize(bytes)
      # Pubkey fields are hex on the Ruby return shape (BRC-100 PubKeyHex);
      # serialize accepts binary OR hex input via pubkey_bytes.
      expect(back[:prover]).to eq(prover_hex)
      expect(back[:verifier]).to eq(verifier_hex)
      expect(back[:counterparty]).to eq(counterparty_hex)
      expect(back[:revelation_time]).to eq('2024-01-01T00:00:00Z')
      expect(back[:encrypted_linkage]).to eq("\xAB\xCD".b)
      expect(back[:encrypted_linkage_proof]).to eq("\xEF".b)
    end

    it 'accepts hex-encoded pubkeys on serialize and round-trips to hex' do
      result_with_hex = full_result.merge(prover: prover_hex, verifier: verifier_hex, counterparty: counterparty_hex)
      back = mod::Result.deserialize(mod::Result.serialize(result_with_hex))
      expect(back[:prover]).to eq(prover_hex)
      expect(back[:verifier]).to eq(verifier_hex)
      expect(back[:counterparty]).to eq(counterparty_hex)
    end

    it 'round-trips empty encrypted linkage' do
      result = full_result.merge(encrypted_linkage: ''.b, encrypted_linkage_proof: ''.b)
      back = mod::Result.deserialize(mod::Result.serialize(result))
      expect(back[:encrypted_linkage]).to eq(''.b)
      expect(back[:encrypted_linkage_proof]).to eq(''.b)
    end
  end
end
