# frozen_string_literal: true

require 'spec_helper'

require 'bsv-sdk'

# A well-known compressed public key (33 bytes) used as a test identity key.
# Corresponds to PrivateKey(1) on secp256k1.
SHIP_IDENTITY_KEY_HEX = '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'
SHIP_IDENTITY_KEY_BIN = [SHIP_IDENTITY_KEY_HEX].pack('H*')

RSpec.describe BSV::Overlay::AdminTokenTemplate do
  # A dummy P2PKH lock script used as the underlying lock in test PushDrop scripts.
  let(:dummy_pubkey_hash) { ("\x00" * 20).b }
  let(:lock_script) { BSV::Script::Script.p2pkh_lock(dummy_pubkey_hash) }

  # A Client backed by PrivateKey(1), used for deterministic lock/unlock tests.
  let(:private_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(1)) }
  let(:wallet) { BSV::Wallet::ProtoWallet.new(private_key) }

  def ship_script(domain: 'example.com', topic: 'tm_tests', identity_key: SHIP_IDENTITY_KEY_BIN)
    BSV::Script::Script.pushdrop_lock(
      ['SHIP'.b, identity_key, domain.encode('binary'), topic.encode('binary')],
      lock_script
    )
  end

  def slap_script(domain: 'lookup.example.com', service: 'ls_tests', identity_key: SHIP_IDENTITY_KEY_BIN)
    BSV::Script::Script.pushdrop_lock(
      ['SLAP'.b, identity_key, domain.encode('binary'), service.encode('binary')],
      lock_script
    )
  end

  describe '.decode' do
    context 'with a valid SHIP advertisement' do
      subject(:result) { described_class.decode(ship_script) }

      it 'returns an Advertisement' do
        expect(result).to be_a(BSV::Overlay::AdminTokenTemplate::Advertisement)
      end

      it 'decodes the protocol as SHIP' do
        expect(result.protocol).to eq('SHIP')
      end

      it 'decodes the identity key as hex' do
        expect(result.identity_key).to eq(SHIP_IDENTITY_KEY_HEX)
      end

      it 'decodes the domain' do
        expect(result.domain).to eq('example.com')
      end

      it 'decodes the topic_or_service' do
        expect(result.topic_or_service).to eq('tm_tests')
      end
    end

    context 'with a valid SLAP advertisement' do
      subject(:result) { described_class.decode(slap_script) }

      it 'decodes the protocol as SLAP' do
        expect(result.protocol).to eq('SLAP')
      end

      it 'decodes the identity key as hex' do
        expect(result.identity_key).to eq(SHIP_IDENTITY_KEY_HEX)
      end

      it 'decodes the domain' do
        expect(result.domain).to eq('lookup.example.com')
      end

      it 'decodes the topic_or_service' do
        expect(result.topic_or_service).to eq('ls_tests')
      end
    end

    context 'with a non-PushDrop script' do
      it 'returns nil for a P2PKH script' do
        script = BSV::Script::Script.p2pkh_lock(dummy_pubkey_hash)
        expect(described_class.decode(script)).to be_nil
      end
    end

    context 'with a nil or empty script' do
      it 'returns nil for nil' do
        expect(described_class.decode(nil)).to be_nil
      end

      it 'returns nil for an empty script' do
        expect(described_class.decode(BSV::Script::Script.new)).to be_nil
      end
    end

    context 'with a PushDrop script with fewer than 4 fields' do
      it 'raises OverlayError' do
        script = BSV::Script::Script.pushdrop_lock(
          ['SHIP'.b, SHIP_IDENTITY_KEY_BIN],
          lock_script
        )
        expect { described_class.decode(script) }.to raise_error(BSV::Overlay::OverlayError, /4 fields/)
      end
    end

    context 'with a PushDrop script containing exactly 3 fields' do
      it 'raises OverlayError' do
        script = BSV::Script::Script.pushdrop_lock(
          ['SHIP'.b, SHIP_IDENTITY_KEY_BIN, 'example.com'.b],
          lock_script
        )
        expect { described_class.decode(script) }.to raise_error(BSV::Overlay::OverlayError)
      end
    end

    context 'with a PushDrop script containing an invalid protocol' do
      it 'raises OverlayError' do
        script = BSV::Script::Script.pushdrop_lock(
          ['NOPE'.b, SHIP_IDENTITY_KEY_BIN, 'example.com'.b, 'tm_tests'.b],
          lock_script
        )
        expect { described_class.decode(script) }.to raise_error(BSV::Overlay::OverlayError, /protocol/)
      end
    end

    context 'with null byte normalisation' do
      it 'treats a single null byte in the domain field as an empty string' do
        script = BSV::Script::Script.pushdrop_lock(
          ['SHIP'.b, SHIP_IDENTITY_KEY_BIN, "\x00".b, 'tm_tests'.b],
          lock_script
        )
        result = described_class.decode(script)
        expect(result.domain).to eq('')
      end

      it 'treats a single null byte in the topic_or_service field as an empty string' do
        script = BSV::Script::Script.pushdrop_lock(
          ['SHIP'.b, SHIP_IDENTITY_KEY_BIN, 'example.com'.b, "\x00".b],
          lock_script
        )
        result = described_class.decode(script)
        expect(result.topic_or_service).to eq('')
      end
    end

    context 'when verifying round-trip encode/decode via pushdrop_lock' do
      it 'round-trips a SHIP advertisement' do
        script = ship_script(domain: 'myhost.bsvb.tech', topic: 'tm_payments')
        result = described_class.decode(script)

        expect(result.protocol).to eq('SHIP')
        expect(result.identity_key).to eq(SHIP_IDENTITY_KEY_HEX)
        expect(result.domain).to eq('myhost.bsvb.tech')
        expect(result.topic_or_service).to eq('tm_payments')
      end

      it 'round-trips a SLAP advertisement' do
        script = slap_script(domain: 'lookup.bsvb.tech', service: 'ls_ship')
        result = described_class.decode(script)

        expect(result.protocol).to eq('SLAP')
        expect(result.identity_key).to eq(SHIP_IDENTITY_KEY_HEX)
        expect(result.domain).to eq('lookup.bsvb.tech')
        expect(result.topic_or_service).to eq('ls_ship')
      end
    end
  end

  describe '#lock' do
    let(:template) { described_class.new(wallet) }

    context 'with a SHIP advertisement' do
      subject(:locking_script) { template.lock('SHIP', 'test.com', 'tm_tests') }

      it 'returns a PushDrop script' do
        expect(locking_script).to be_a(BSV::Script::Script)
        expect(locking_script.pushdrop?).to be true
      end

      it 'produces a script that decode can parse' do
        decoded = described_class.decode(locking_script)
        expect(decoded).to be_a(BSV::Overlay::AdminTokenTemplate::Advertisement)
      end

      it 'encodes the protocol as SHIP' do
        decoded = described_class.decode(locking_script)
        expect(decoded.protocol).to eq('SHIP')
      end

      it 'encodes the domain' do
        decoded = described_class.decode(locking_script)
        expect(decoded.domain).to eq('test.com')
      end

      it 'encodes the topic_or_service' do
        decoded = described_class.decode(locking_script)
        expect(decoded.topic_or_service).to eq('tm_tests')
      end

      it 'encodes the wallet identity key' do
        decoded = described_class.decode(locking_script)
        identity_hex = wallet.get_public_key(identity_key: true)[:public_key]
        expect(decoded.identity_key).to eq(identity_hex)
      end
    end

    context 'with a SLAP advertisement' do
      subject(:locking_script) { template.lock('SLAP', 'lookup.example.com', 'ls_tests') }

      it 'returns a PushDrop script' do
        expect(locking_script).to be_a(BSV::Script::Script)
        expect(locking_script.pushdrop?).to be true
      end

      it 'encodes the protocol as SLAP' do
        decoded = described_class.decode(locking_script)
        expect(decoded.protocol).to eq('SLAP')
      end

      it 'encodes the domain' do
        decoded = described_class.decode(locking_script)
        expect(decoded.domain).to eq('lookup.example.com')
      end

      it 'encodes the topic_or_service' do
        decoded = described_class.decode(locking_script)
        expect(decoded.topic_or_service).to eq('ls_tests')
      end
    end

    context 'with an invalid protocol' do
      it 'raises OverlayError for an unrecognised protocol string' do
        expect { template.lock('INVALID', 'test.com', 'tm_tests') }
          .to raise_error(BSV::Overlay::OverlayError, /SHIP.*SLAP/)
      end

      it 'raises OverlayError for a lowercase protocol string' do
        expect { template.lock('ship', 'test.com', 'tm_tests') }
          .to raise_error(BSV::Overlay::OverlayError)
      end

      it 'raises OverlayError for an empty string' do
        expect { template.lock('', 'test.com', 'tm_tests') }
          .to raise_error(BSV::Overlay::OverlayError)
      end
    end

    context 'with an originator' do
      it 'accepts an originator on construction without raising' do
        template_with_originator = described_class.new(wallet, originator: 'test.example.com')
        expect { template_with_originator.lock('SHIP', 'test.com', 'tm_tests') }
          .not_to raise_error
      end
    end

    context 'when verifying the identity key round-trip' do
      it 'embeds the wallet identity key in the locking script' do
        identity_hex = wallet.get_public_key(identity_key: true)[:public_key]
        locking_script = template.lock('SHIP', 'myhost.bsvb.tech', 'tm_payments')
        decoded = described_class.decode(locking_script)
        expect(decoded.identity_key).to eq(identity_hex)
      end
    end
  end

  describe '#unlock' do
    let(:template) { described_class.new(wallet) }

    context 'with an invalid protocol' do
      it 'raises OverlayError' do
        expect { template.unlock('INVALID') }
          .to raise_error(BSV::Overlay::OverlayError)
      end
    end

    context 'with a valid protocol' do
      it 'returns an Unlocker for SHIP' do
        expect(template.unlock('SHIP')).to be_a(BSV::Overlay::AdminTokenTemplate::Unlocker)
      end

      it 'returns an Unlocker for SLAP' do
        expect(template.unlock('SLAP')).to be_a(BSV::Overlay::AdminTokenTemplate::Unlocker)
      end

      it 'estimates the script length as 73 bytes' do
        unlocker = template.unlock('SHIP')
        expect(unlocker.estimated_length(nil, 0)).to eq(73)
      end
    end
  end

  describe 'lock + unlock round-trip (script verification)' do
    # Helper: build a signed spending transaction and verify its input scripts.
    def build_and_verify(protocol, domain, topic_or_service)
      template = described_class.new(wallet)
      locking_script = template.lock(protocol, domain, topic_or_service)
      satoshis = 1_000

      # Source transaction: contains the locked output.
      source_tx = BSV::Transaction::Tx.new
      dummy_input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x00" * 32,
        prev_tx_out_index: 0
      )
      dummy_input.source_locking_script = BSV::Script::Script.p2pkh_lock("\x00" * 20)
      dummy_input.source_satoshis = satoshis + 100
      dummy_input.unlocking_script = BSV::Script::Script.new
      source_tx.add_input(dummy_input)
      source_tx.add_output(
        BSV::Transaction::TransactionOutput.new(satoshis: satoshis, locking_script: locking_script)
      )

      # Spending transaction: spends the locked output.
      spend_tx = BSV::Transaction::Tx.new
      spend_input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: source_tx.wtxid,
        prev_tx_out_index: 0,
        sequence: 0xffffffff
      )
      spend_input.source_transaction = source_tx
      spend_input.source_satoshis = satoshis
      spend_input.source_locking_script = locking_script
      spend_tx.add_input(spend_input)
      spend_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: satoshis - 100,
          locking_script: BSV::Script::Script.p2pkh_lock("\x00" * 20)
        )
      )

      # Sign and verify.
      unlocker = template.unlock(protocol)
      spend_tx.inputs[0].unlocking_script = unlocker.sign(spend_tx, 0)
      spend_tx.verify_input(0)
    end

    it 'verifies a SHIP lock + unlock' do
      expect(build_and_verify('SHIP', 'test.com', 'tm_tests')).to be true
    end

    it 'verifies a SLAP lock + unlock' do
      expect(build_and_verify('SLAP', 'lookup.example.com', 'ls_tests')).to be true
    end

    it 'verifies with an empty domain' do
      expect(build_and_verify('SHIP', '', 'tm_tests')).to be true
    end

    it 'verifies with an empty topic_or_service' do
      expect(build_and_verify('SLAP', 'lookup.example.com', '')).to be true
    end
  end
end
