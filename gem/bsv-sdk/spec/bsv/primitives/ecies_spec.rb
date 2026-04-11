# frozen_string_literal: true

RSpec.describe BSV::Primitives::ECIES do
  # TypeScript SDK test vector keys
  let(:alice_privkey) { BSV::Primitives::PrivateKey.from_hex('77e06abc52bf065cb5164c5deca839d0276911991a2730be4d8d0a0307de7ceb') }
  let(:bob_privkey) { BSV::Primitives::PrivateKey.from_hex('2b57c7c5e408ce927eef5e2efb49cfdadde77961d342daa72284bb3d6590862d') }
  let(:plaintext) { 'this is my test message' }

  # Expected ciphertexts (base64) from TypeScript SDK
  let(:alice_to_bob_b64) do
    'QklFMQM55QTWSSsILaluEejwOXlrBs1IVcEB4kkqbxDz4Fap53XHOt6L3tKmrXho6yj6phfoiMkBOhUldRPnEI4fSZXbvZJHgyAzxA6SoujduvJXv+A9ri3po9veilrmc8p6dwo='
  end
  let(:bob_to_alice_b64) do
    'QklFMQOGFyMXLo9Qv047K3BYJhmnJgt58EC8skYP/R2QU/U0yXXHOt6L3tKmrXho6yj6phfoiMkBOhUldRPnEI4fSZXbiaH4FsxKIOOvzolIFVAS0FplUmib2HnlAM1yP/iiPsU='
  end

  # Go SDK test vector
  let(:go_wif) { 'L211enC224G1kV8pyyq7bjVd9SxZebnRYEzzM3i7ZHCc1c5E7dQu' }
  let(:go_privkey) { BSV::Primitives::PrivateKey.from_wif(go_wif) }
  let(:go_plaintext) { 'hello world' }
  let(:go_ciphertext_b64) do
    'QklFMQO7zpX/GS4XpthCy6/hT38ZKsBGbn8JKMGHOY5ifmaoT890Krt9cIRk/ULXaB5uC08owRICzenFbm31pZGu0gCM2uOxpofwHacKidwZ0Q7aEw=='
  end

  describe '.encrypt' do
    context 'with TypeScript SDK test vectors' do
      it 'Alice encrypting to Bob matches expected ciphertext' do
        result = described_class.encrypt(plaintext, bob_privkey.public_key, private_key: alice_privkey)
        expect([result].pack('m0')).to eq(alice_to_bob_b64)
      end

      it 'Bob encrypting to Alice matches expected ciphertext' do
        result = described_class.encrypt(plaintext, alice_privkey.public_key, private_key: bob_privkey)
        expect([result].pack('m0')).to eq(bob_to_alice_b64)
      end
    end

    context 'with Go SDK test vector' do
      it 'self-encryption matches expected ciphertext' do
        result = described_class.encrypt(go_plaintext, go_privkey.public_key, private_key: go_privkey)
        expect([result].pack('m0')).to eq(go_ciphertext_b64)
      end
    end

    context 'with ephemeral key' do
      it 'produces different ciphertexts each time' do
        c1 = described_class.encrypt(plaintext, bob_privkey.public_key)
        c2 = described_class.encrypt(plaintext, bob_privkey.public_key)
        expect(c1).not_to eq(c2)
      end

      it 'produces output that can be decrypted' do
        ciphertext = described_class.encrypt(plaintext, bob_privkey.public_key)
        result = described_class.decrypt(ciphertext, bob_privkey)
        expect(result).to eq(plaintext.b)
      end
    end
  end

  describe '.decrypt' do
    context 'with TypeScript SDK test vectors' do
      it 'Bob decrypts Alice-to-Bob message' do
        data = alice_to_bob_b64.unpack1('m0')
        result = described_class.decrypt(data, bob_privkey)
        expect(result).to eq(plaintext.b)
      end

      it 'Alice decrypts Bob-to-Alice message' do
        data = bob_to_alice_b64.unpack1('m0')
        result = described_class.decrypt(data, alice_privkey)
        expect(result).to eq(plaintext.b)
      end
    end

    context 'with Go SDK test vector' do
      it 'decrypts the self-encrypted message' do
        data = go_ciphertext_b64.unpack1('m0')
        result = described_class.decrypt(data, go_privkey)
        expect(result).to eq(go_plaintext.b)
      end
    end
  end

  describe 'round-trip' do
    it 'works with an empty message' do
      ciphertext = described_class.encrypt('', bob_privkey.public_key, private_key: alice_privkey)
      result = described_class.decrypt(ciphertext, bob_privkey)
      expect(result).to eq(''.b)
    end

    [1, 15, 16, 17, 31, 32, 33, 1000].each do |size|
      it "works with a #{size}-byte message" do
        message = "\xAB".b * size
        ciphertext = described_class.encrypt(message, bob_privkey.public_key, private_key: alice_privkey)
        result = described_class.decrypt(ciphertext, bob_privkey)
        expect(result).to eq(message)
      end
    end

    it 'works with binary data' do
      message = (0..255).map(&:chr).join.b
      ciphertext = described_class.encrypt(message, bob_privkey.public_key, private_key: alice_privkey)
      result = described_class.decrypt(ciphertext, bob_privkey)
      expect(result).to eq(message)
    end

    it 'works with self-encryption' do
      ciphertext = described_class.encrypt(plaintext, alice_privkey.public_key, private_key: alice_privkey)
      result = described_class.decrypt(ciphertext, alice_privkey)
      expect(result).to eq(plaintext.b)
    end
  end

  describe 'error handling' do
    it 'raises ArgumentError for data shorter than 85 bytes' do
      expect { described_class.decrypt("\x00" * 84, bob_privkey) }.to raise_error(ArgumentError, /too short/)
    end

    it 'raises ArgumentError for wrong magic bytes' do
      data = "BIE2#{"\x00" * 81}"
      expect { described_class.decrypt(data, bob_privkey) }.to raise_error(ArgumentError, /invalid magic/)
    end

    it 'raises an error for invalid ephemeral pubkey bytes' do
      # Valid magic + 33 bytes of zeros (invalid point) + 16 bytes ciphertext + 32 bytes MAC
      data = 'BIE1'.b + ("\x00" * 33) + ("\x00" * 16) + ("\x00" * 32)
      expect { described_class.decrypt(data, bob_privkey) }.to raise_error(StandardError)
    end

    it 'raises DecryptionError for wrong private key' do
      ciphertext = described_class.encrypt(plaintext, bob_privkey.public_key, private_key: alice_privkey)
      wrong_key = BSV::Primitives::PrivateKey.from_hex('0000000000000000000000000000000000000000000000000000000000000001')
      expect { described_class.decrypt(ciphertext, wrong_key) }.to raise_error(described_class::DecryptionError)
    end

    it 'raises DecryptionError for tampered ciphertext' do
      ciphertext = described_class.encrypt(plaintext, bob_privkey.public_key, private_key: alice_privkey)
      # Flip a byte in the ciphertext region (after magic + pubkey, before MAC)
      tampered = ciphertext.dup
      tampered.setbyte(40, tampered.getbyte(40) ^ 0xFF)
      expect { described_class.decrypt(tampered, bob_privkey) }.to raise_error(described_class::DecryptionError)
    end

    it 'raises DecryptionError for tampered MAC' do
      ciphertext = described_class.encrypt(plaintext, bob_privkey.public_key, private_key: alice_privkey)
      tampered = ciphertext.dup
      tampered.setbyte(-1, tampered.getbyte(-1) ^ 0xFF)
      expect { described_class.decrypt(tampered, bob_privkey) }.to raise_error(described_class::DecryptionError)
    end
  end

  describe 'output format' do
    let(:ciphertext) { described_class.encrypt(plaintext, bob_privkey.public_key, private_key: alice_privkey) }

    it 'starts with BIE1 magic' do
      expect(ciphertext[0, 4]).to eq('BIE1'.b)
    end

    it 'has a compressed pubkey at offset 4' do
      prefix = ciphertext.getbyte(4)
      expect(prefix).to eq(0x02).or eq(0x03)
      # Verify it parses as a valid public key
      expect { BSV::Primitives::PublicKey.from_bytes(ciphertext[4, 33]) }.not_to raise_error
    end

    it 'ends with a 32-byte MAC' do
      # Total = 4 (magic) + 33 (pubkey) + ciphertext + 32 (MAC)
      # Minimum ciphertext is 16 bytes (one AES block with PKCS7 padding for 23-byte message = 32 bytes)
      expect(ciphertext.bytesize).to be >= 85
    end

    it 'returns ASCII-8BIT encoding' do
      expect(ciphertext.encoding).to eq(Encoding::ASCII_8BIT)
    end
  end
end
