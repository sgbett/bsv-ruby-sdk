# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

# Cross-SDK conformance tests for BRC-100 wallet crypto methods.
#
# These vectors are extracted from the TypeScript SDK's ProtoWallet.test.ts
# and use pinned keys and expected outputs. Any BRC-100-compliant wallet
# implementation must produce identical results for these inputs.
#
# Reference: ts-sdk/src/wallet/__tests/ProtoWallet.test.ts
RSpec.describe 'BRC-100 Client cross-SDK conformance', :conformance do
  # -------------------------------------------------------------------------
  # BRC-3 Signature Compliance Vector
  # -------------------------------------------------------------------------
  describe 'BRC-3 signature compliance vector' do
    let(:wallet) { BSV::Wallet::Client.new('anyone', storage: BSV::Wallet::Store::Memory.new) }

    let(:known_signature_bytes) do
      [
        48, 68, 2, 32, 43, 34, 58, 156, 219, 32, 50, 70, 29, 240, 155, 137, 88,
        60, 200, 95, 243, 198, 201, 21, 56, 82, 141, 112, 69, 196, 170, 73, 156,
        6, 44, 48, 2, 32, 118, 125, 254, 201, 44, 87, 177, 170, 93, 11, 193,
        134, 18, 70, 9, 31, 234, 27, 170, 177, 54, 96, 181, 140, 166, 196, 144,
        14, 230, 118, 106, 105
      ]
    end

    it 'verifies the ts-sdk BRC-3 compliance signature' do
      result = wallet.verify_signature({
                                         data: 'BRC-3 Compliance Validated!'.bytes,
                                         signature: known_signature_bytes,
                                         protocol_id: [2, 'brc3 test'],
                                         key_id: '42',
                                         counterparty: '0294c479f762f6baa97fbcd4393564c1d7bd8336ebd15928135bbcf575cd1a71a1'
                                       })
      expect(result[:valid]).to be true
    end
  end

  # -------------------------------------------------------------------------
  # BRC-2 HMAC Compliance Vector
  # -------------------------------------------------------------------------
  describe 'BRC-2 HMAC compliance vector' do
    let(:wallet) do
      key = BSV::Primitives::PrivateKey.from_hex('6a2991c9de20e38b31d7ea147bf55f5039e4bbc073160f5e0d541d1f17e321b8')
      BSV::Wallet::Client.new(key, storage: BSV::Wallet::Store::Memory.new)
    end

    let(:known_hmac_bytes) do
      [
        81, 240, 18, 153, 163, 45, 174, 85, 9, 246, 142, 125, 209, 133, 82, 76,
        254, 103, 46, 182, 86, 59, 219, 61, 126, 30, 176, 232, 233, 100, 234,
        14
      ]
    end

    it 'verifies the ts-sdk BRC-2 HMAC compliance value' do
      result = wallet.verify_hmac({
                                    data: 'BRC-2 HMAC Compliance Validated!'.bytes,
                                    hmac: known_hmac_bytes,
                                    protocol_id: [2, 'brc2 test'],
                                    key_id: '42',
                                    counterparty: '0294c479f762f6baa97fbcd4393564c1d7bd8336ebd15928135bbcf575cd1a71a1'
                                  })
      expect(result[:valid]).to be true
    end

    it 'produces the exact same HMAC bytes as the ts-sdk' do
      result = wallet.create_hmac({
                                    data: 'BRC-2 HMAC Compliance Validated!'.bytes,
                                    protocol_id: [2, 'brc2 test'],
                                    key_id: '42',
                                    counterparty: '0294c479f762f6baa97fbcd4393564c1d7bd8336ebd15928135bbcf575cd1a71a1'
                                  })
      expect(result[:hmac]).to eq(known_hmac_bytes)
    end
  end

  # -------------------------------------------------------------------------
  # BRC-2 Encryption Compliance Vector
  # -------------------------------------------------------------------------
  describe 'BRC-2 encryption compliance vector' do
    let(:wallet) do
      key = BSV::Primitives::PrivateKey.from_hex('6a2991c9de20e38b31d7ea147bf55f5039e4bbc073160f5e0d541d1f17e321b8')
      BSV::Wallet::Client.new(key, storage: BSV::Wallet::Store::Memory.new)
    end

    let(:known_ciphertext_bytes) do
      [
        252, 203, 216, 184, 29, 161, 223, 212, 16, 193, 94, 99, 31, 140, 99, 43,
        61, 236, 184, 67, 54, 105, 199, 47, 11, 19, 184, 127, 2, 165, 125, 9,
        188, 195, 196, 39, 120, 130, 213, 95, 186, 89, 64, 28, 1, 80, 20, 213,
        159, 133, 98, 253, 128, 105, 113, 247, 197, 152, 236, 64, 166, 207, 113,
        134, 65, 38, 58, 24, 127, 145, 140, 206, 47, 70, 146, 84, 186, 72, 95,
        35, 154, 112, 178, 55, 72, 124
      ]
    end

    it 'decrypts the ts-sdk BRC-2 compliance ciphertext' do
      result = wallet.decrypt({
                                ciphertext: known_ciphertext_bytes,
                                protocol_id: [2, 'brc2 test'],
                                key_id: '42',
                                counterparty: '0294c479f762f6baa97fbcd4393564c1d7bd8336ebd15928135bbcf575cd1a71a1'
                              })
      plaintext_string = result[:plaintext].pack('C*')
      expect(plaintext_string).to eq('BRC-2 Encryption Compliance Validated!')
    end
  end

  # -------------------------------------------------------------------------
  # Cross-wallet key derivation symmetry
  # -------------------------------------------------------------------------
  describe 'key derivation symmetry' do
    let(:user_key) { BSV::Primitives::PrivateKey.generate }
    let(:counterparty_key) { BSV::Primitives::PrivateKey.generate }
    let(:user) { BSV::Wallet::Client.new(user_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:counterparty_wallet) { BSV::Wallet::Client.new(counterparty_key, storage: BSV::Wallet::Store::Memory.new) }

    it 'derives the same public key from both sides (BRC-42 symmetry)' do
      derived_for_counterparty = user.get_public_key({
                                                       protocol_id: [2, 'tests'],
                                                       key_id: '4',
                                                       counterparty: counterparty_key.public_key.to_hex
                                                     })

      derived_by_counterparty = counterparty_wallet.get_public_key({
                                                                     protocol_id: [2, 'tests'],
                                                                     key_id: '4',
                                                                     counterparty: user_key.public_key.to_hex,
                                                                     for_self: true
                                                                   })

      expect(derived_for_counterparty[:public_key]).to eq(derived_by_counterparty[:public_key])
    end
  end

  # -------------------------------------------------------------------------
  # Cross-wallet encrypt/decrypt
  # -------------------------------------------------------------------------
  describe 'cross-wallet encrypt/decrypt' do
    let(:user_key) { BSV::Primitives::PrivateKey.generate }
    let(:counterparty_key) { BSV::Primitives::PrivateKey.generate }
    let(:user) { BSV::Wallet::Client.new(user_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:counterparty_wallet) { BSV::Wallet::Client.new(counterparty_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:sample_data) { [3, 1, 4, 1, 5, 9] }

    it 'encrypts messages decryptable by the counterparty' do
      encrypted = user.encrypt({
                                 plaintext: sample_data,
                                 protocol_id: [2, 'tests'],
                                 key_id: '4',
                                 counterparty: counterparty_key.public_key.to_hex
                               })

      decrypted = counterparty_wallet.decrypt({
                                                ciphertext: encrypted[:ciphertext],
                                                protocol_id: [2, 'tests'],
                                                key_id: '4',
                                                counterparty: user_key.public_key.to_hex
                                              })

      expect(decrypted[:plaintext]).to eq(sample_data)
    end

    it 'fails to decrypt with wrong protocol' do
      encrypted = user.encrypt({
                                 plaintext: sample_data,
                                 protocol_id: [2, 'tests'],
                                 key_id: '4',
                                 counterparty: counterparty_key.public_key.to_hex
                               })

      expect do
        counterparty_wallet.decrypt({
                                      ciphertext: encrypted[:ciphertext],
                                      protocol_id: [1, 'tests'],
                                      key_id: '4',
                                      counterparty: user_key.public_key.to_hex
                                    })
      end.to raise_error(StandardError)
    end

    it 'fails to decrypt with wrong key_id' do
      encrypted = user.encrypt({
                                 plaintext: sample_data,
                                 protocol_id: [2, 'tests'],
                                 key_id: '4',
                                 counterparty: counterparty_key.public_key.to_hex
                               })

      expect do
        counterparty_wallet.decrypt({
                                      ciphertext: encrypted[:ciphertext],
                                      protocol_id: [2, 'tests'],
                                      key_id: '5',
                                      counterparty: user_key.public_key.to_hex
                                    })
      end.to raise_error(StandardError)
    end
  end

  # -------------------------------------------------------------------------
  # Cross-wallet sign/verify
  # -------------------------------------------------------------------------
  describe 'cross-wallet sign/verify' do
    let(:user_key) { BSV::Primitives::PrivateKey.generate }
    let(:counterparty_key) { BSV::Primitives::PrivateKey.generate }
    let(:user) { BSV::Wallet::Client.new(user_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:counterparty_wallet) { BSV::Wallet::Client.new(counterparty_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:sample_data) { [3, 1, 4, 1, 5, 9] }

    it 'signs messages verifiable by the counterparty' do
      signed = user.create_signature({
                                       data: sample_data,
                                       protocol_id: [2, 'tests'],
                                       key_id: '4',
                                       counterparty: counterparty_key.public_key.to_hex
                                     })

      verified = counterparty_wallet.verify_signature({
                                                        signature: signed[:signature],
                                                        data: sample_data,
                                                        protocol_id: [2, 'tests'],
                                                        key_id: '4',
                                                        counterparty: user_key.public_key.to_hex
                                                      })

      expect(verified[:valid]).to be true
    end

    it 'fails to verify with wrong data' do
      signed = user.create_signature({
                                       data: sample_data,
                                       protocol_id: [2, 'tests'],
                                       key_id: '4',
                                       counterparty: counterparty_key.public_key.to_hex
                                     })

      expect do
        counterparty_wallet.verify_signature({
                                               signature: signed[:signature],
                                               data: [0] + sample_data,
                                               protocol_id: [2, 'tests'],
                                               key_id: '4',
                                               counterparty: user_key.public_key.to_hex
                                             })
      end.to raise_error(BSV::Wallet::InvalidSignatureError)
    end
  end

  # -------------------------------------------------------------------------
  # Cross-wallet HMAC
  # -------------------------------------------------------------------------
  describe 'cross-wallet HMAC' do
    let(:user_key) { BSV::Primitives::PrivateKey.generate }
    let(:counterparty_key) { BSV::Primitives::PrivateKey.generate }
    let(:user) { BSV::Wallet::Client.new(user_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:counterparty_wallet) { BSV::Wallet::Client.new(counterparty_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:sample_data) { [3, 1, 4, 1, 5, 9] }

    it 'computes HMACs verifiable by the counterparty' do
      hmac_result = user.create_hmac({
                                       data: sample_data,
                                       protocol_id: [2, 'tests'],
                                       key_id: '4',
                                       counterparty: counterparty_key.public_key.to_hex
                                     })

      verified = counterparty_wallet.verify_hmac({
                                                   hmac: hmac_result[:hmac],
                                                   data: sample_data,
                                                   protocol_id: [2, 'tests'],
                                                   key_id: '4',
                                                   counterparty: user_key.public_key.to_hex
                                                 })

      expect(verified[:valid]).to be true
      expect(hmac_result[:hmac].length).to eq(32)
    end
  end

  # -------------------------------------------------------------------------
  # Default counterparty behaviour
  # -------------------------------------------------------------------------
  describe 'default counterparty behaviour' do
    let(:user_key) { BSV::Primitives::PrivateKey.generate }
    let(:user) { BSV::Wallet::Client.new(user_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:sample_data) { [3, 1, 4, 1, 5, 9] }

    it 'defaults to "self" for HMAC when no counterparty specified' do
      hmac_result = user.create_hmac({
                                       data: sample_data,
                                       protocol_id: [2, 'tests'],
                                       key_id: '4'
                                     })

      verified = user.verify_hmac({
                                    hmac: hmac_result[:hmac],
                                    data: sample_data,
                                    protocol_id: [2, 'tests'],
                                    key_id: '4',
                                    counterparty: 'self'
                                  })

      expect(verified[:valid]).to be true
    end

    it 'defaults to "self" for getPublicKey when no counterparty specified' do
      without_cp = user.get_public_key({
                                         protocol_id: [2, 'tests'],
                                         key_id: '4'
                                       })

      with_self = user.get_public_key({
                                        protocol_id: [2, 'tests'],
                                        key_id: '4',
                                        counterparty: 'self'
                                      })

      expect(without_cp[:public_key]).to eq(with_self[:public_key])
    end

    it 'defaults to "self" for encrypt/decrypt when no counterparty specified' do
      encrypted = user.encrypt({
                                 plaintext: sample_data,
                                 protocol_id: [2, 'tests'],
                                 key_id: '4'
                               })

      decrypted = user.decrypt({
                                 ciphertext: encrypted[:ciphertext],
                                 protocol_id: [2, 'tests'],
                                 key_id: '4',
                                 counterparty: 'self'
                               })

      expect(decrypted[:plaintext]).to eq(sample_data)
    end
  end

  # -------------------------------------------------------------------------
  # Counterparty key linkage (BRC-69)
  # -------------------------------------------------------------------------
  describe 'counterparty key linkage (BRC-69)' do
    let(:prover_key) { BSV::Primitives::PrivateKey.generate }
    let(:counterparty_key) { BSV::Primitives::PrivateKey.generate }
    let(:verifier_key) { BSV::Primitives::PrivateKey.generate }
    let(:prover) { BSV::Wallet::Client.new(prover_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:verifier) { BSV::Wallet::Client.new(verifier_key, storage: BSV::Wallet::Store::Memory.new) }

    it 'reveals counterparty linkage decryptable by the verifier' do
      revelation = prover.reveal_counterparty_key_linkage({
                                                            counterparty: counterparty_key.public_key.to_hex,
                                                            verifier: verifier_key.public_key.to_hex
                                                          })

      decrypted = verifier.decrypt({
                                     ciphertext: revelation[:encrypted_linkage],
                                     protocol_id: [2, 'counterparty linkage revelation'],
                                     key_id: revelation[:revelation_time],
                                     counterparty: prover_key.public_key.to_hex
                                   })

      # The decrypted linkage should equal the ECDH shared secret
      expected_linkage = prover_key.derive_shared_secret(counterparty_key.public_key).compressed
      expect(decrypted[:plaintext]).to eq(expected_linkage.unpack('C*'))
    end
  end

  # -------------------------------------------------------------------------
  # Specific key linkage (BRC-69)
  # -------------------------------------------------------------------------
  describe 'specific key linkage (BRC-69)' do
    let(:prover_key) { BSV::Primitives::PrivateKey.generate }
    let(:counterparty_key) { BSV::Primitives::PrivateKey.generate }
    let(:verifier_key) { BSV::Primitives::PrivateKey.generate }
    let(:prover) { BSV::Wallet::Client.new(prover_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:verifier) { BSV::Wallet::Client.new(verifier_key, storage: BSV::Wallet::Store::Memory.new) }
    let(:protocol_id) { [0, 'tests'] }
    let(:key_id) { 'test key id' }

    it 'reveals specific linkage decryptable and verifiable by the verifier' do
      revelation = prover.reveal_specific_key_linkage({
                                                        counterparty: counterparty_key.public_key.to_hex,
                                                        verifier: verifier_key.public_key.to_hex,
                                                        protocol_id: protocol_id,
                                                        key_id: key_id
                                                      })

      decrypted = verifier.decrypt({
                                     ciphertext: revelation[:encrypted_linkage],
                                     protocol_id: [2, "specific linkage revelation #{protocol_id[0]} #{protocol_id[1]}"],
                                     key_id: key_id,
                                     counterparty: prover_key.public_key.to_hex
                                   })

      # Compute expected linkage: HMAC(shared_secret, invoice_number)
      shared_secret = prover_key.derive_shared_secret(counterparty_key.public_key).compressed
      invoice_number = "#{protocol_id[0]}-#{protocol_id[1]}-#{key_id}"
      expected_linkage = BSV::Primitives::Digest.hmac_sha256(shared_secret, invoice_number.encode('UTF-8'))

      expect(decrypted[:plaintext]).to eq(expected_linkage.unpack('C*'))
    end
  end
end
