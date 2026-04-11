# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::ExtendedKey do
  # BIP-32 Test Vector 1
  # https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#test-vector-1
  describe 'BIP-32 test vector 1' do
    let(:seed) { ['000102030405060708090a0b0c0d0e0f'].pack('H*') }
    let(:master) { described_class.from_seed(seed) }

    vectors = [
      {
        path: 'm',
        xpub: 'xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8',
        xprv: 'xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi'
      },
      {
        path: "m/0'",
        xpub: 'xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw',
        xprv: 'xprv9uHRZZhk6KAJC1avXpDAp4MDc3sQKNxDiPvvkX8Br5ngLNv1TxvUxt4cV1rGL5hj6KCesnDYUhd7oWgT11eZG7XnxHrnYeSvkzY7d2bhkJ7'
      },
      {
        path: "m/0'/1",
        xpub: 'xpub6ASuArnXKPbfEwhqN6e3mwBcDTgzisQN1wXN9BJcM47sSikHjJf3UFHKkNAWbWMiGj7Wf5uMash7SyYq527Hqck2AxYysAA7xmALppuCkwQ',
        xprv: 'xprv9wTYmMFdV23N2TdNG573QoEsfRrWKQgWeibmLntzniatZvR9BmLnvSxqu53Kw1UmYPxLgboyZQaXwTCg8MSY3H2EU4pWcQDnRnrVA1xe8fs'
      },
      {
        path: "m/0'/1/2'",
        xpub: 'xpub6D4BDPcP2GT577Vvch3R8wDkScZWzQzMMUm3PWbmWvVJrZwQY4VUNgqFJPMM3No2dFDFGTsxxpG5uJh7n7epu4trkrX7x7DogT5Uv6fcLW5',
        xprv: 'xprv9z4pot5VBttmtdRTWfWQmoH1taj2axGVzFqSb8C9xaxKymcFzXBDptWmT7FwuEzG3ryjH4ktypQSAewRiNMjANTtpgP4mLTj34bhnZX7UiM'
      },
      {
        path: "m/0'/1/2'/2",
        xpub: 'xpub6FHa3pjLCk84BayeJxFW2SP4XRrFd1JYnxeLeU8EqN3vDfZmbqBqaGJAyiLjTAwm6ZLRQUMv1ZACTj37sR62cfN7fe5JnJ7dh8zL4fiyLHV',
        xprv: 'xprvA2JDeKCSNNZky6uBCviVfJSKyQ1mDYahRjijr5idH2WwLsEd4Hsb2Tyh8RfQMuPh7f7RtyzTtdrbdqqsunu5Mm3wDvUAKRHSC34sJ7in334'
      },
      {
        path: "m/0'/1/2'/2/1000000000",
        xpub: 'xpub6H1LXWLaKsWFhvm6RVpEL9P4KfRZSW7abD2ttkWP3SSQvnyA8FSVqNTEcYFgJS2UaFcxupHiYkro49S8yGasTvXEYBVPamhGW6cFJodrTHy',
        xprv: 'xprvA41z7zogVVwxVSgdKUHDy1SKmdb533PjDz7J6N6mV6uS3ze1ai8FHa8kmHScGpWmj4WggLyQjgPie1rFSruoUihUZREPSL39UNdE3BBDu76'
      }
    ]

    vectors.each do |v|
      context "chain #{v[:path]}" do
        let(:derived) { v[:path] == 'm' ? master : master.derive_path(v[:path]) }

        it 'produces the expected xprv' do
          expect(derived.to_s).to eq(v[:xprv])
        end

        it 'produces the expected xpub' do
          expect(derived.neuter.to_s).to eq(v[:xpub])
        end
      end
    end
  end

  # BIP-32 Test Vector 2
  describe 'BIP-32 test vector 2' do
    let(:seed) do
      ['fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a29f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542'].pack('H*')
    end
    let(:master) { described_class.from_seed(seed) }

    vectors = [
      {
        path: 'm',
        xpub: 'xpub661MyMwAqRbcFW31YEwpkMuc5THy2PSt5bDMsktWQcFF8syAmRUapSCGu8ED9W6oDMSgv6Zz8idoc4a6mr8BDzTJY47LJhkJ8UB7WEGuduB',
        xprv: 'xprv9s21ZrQH143K31xYSDQpPDxsXRTUcvj2iNHm5NUtrGiGG5e2DtALGdso3pGz6ssrdK4PFmM8NSpSBHNqPqm55Qn3LqFtT2emdEXVYsCzC2U'
      },
      {
        path: 'm/0',
        xpub: 'xpub69H7F5d8KSRgmmdJg2KhpAK8SR3DjMwAdkxj3ZuxV27CprR9LgpeyGmXUbC6wb7ERfvrnKZjXoUmmDznezpbZb7ap6r1D3tgFxHmwMkQTPH',
        xprv: 'xprv9vHkqa6EV4sPZHYqZznhT2NPtPCjKuDKGY38FBWLvgaDx45zo9WQRUT3dKYnjwih2yJD9mkrocEZXo1ex8G81dwSM1fwqWpWkeS3v86pgKt'
      },
      {
        path: "m/0/2147483647'",
        xpub: 'xpub6ASAVgeehLbnwdqV6UKMHVzgqAG8Gr6riv3Fxxpj8ksbH9ebxaEyBLZ85ySDhKiLDBrQSARLq1uNRts8RuJiHjaDMBU4Zn9h8LZNnBC5y4a',
        xprv: 'xprv9wSp6B7kry3Vj9m1zSnLvN3xH8RdsPP1Mh7fAaR7aRLcQMKTR2vidYEeEg2mUCTAwCd6vnxVrcjfy2kRgVsFawNzmjuHc2YmYRmagcEPdU9'
      },
      {
        path: "m/0/2147483647'/1",
        xpub: 'xpub6DF8uhdarytz3FWdA8TvFSvvAh8dP3283MY7p2V4SeE2wyWmG5mg5EwVvmdMVCQcoNJxGoWaU9DCWh89LojfZ537wTfunKau47EL2dhHKon',
        xprv: 'xprv9zFnWC6h2cLgpmSA46vutJzBcfJ8yaJGg8cX1e5StJh45BBciYTRXSd25UEPVuesF9yog62tGAQtHjXajPPdbRCHuWS6T8XA2ECKADdw4Ef'
      },
      {
        path: "m/0/2147483647'/1/2147483646'",
        xpub: 'xpub6ERApfZwUNrhLCkDtcHTcxd75RbzS1ed54G1LkBUHQVHQKqhMkhgbmJbZRkrgZw4koxb5JaHWkY4ALHY2grBGRjaDMzQLcgJvLJuZZvRcEL',
        xprv: 'xprvA1RpRA33e1JQ7ifknakTFpgNXPmW2YvmhqLQYMmrj4xJXXWYpDPS3xz7iAxn8L39njGVyuoseXzU6rcxFLJ8HFsTjSyQbLYnMpCqE2VbFWc'
      },
      {
        path: "m/0/2147483647'/1/2147483646'/2",
        xpub: 'xpub6FnCn6nSzZAw5Tw7cgR9bi15UV96gLZhjDstkXXxvCLsUXBGXPdSnLFbdpq8p9HmGsApME5hQTZ3emM2rnY5agb9rXpVGyy3bdW6EEgAtqt',
        xprv: 'xprvA2nrNbFZABcdryreWet9Ea4LvTJcGsqrMzxHx98MMrotbir7yrKCEXw7nadnHM8Dq38EGfSh6dqA9QWTyefMLEcBYJUuekgW4BYPJcr9E7j'
      }
    ]

    vectors.each do |v|
      context "chain #{v[:path]}" do
        let(:derived) { v[:path] == 'm' ? master : master.derive_path(v[:path]) }

        it 'produces the expected xprv' do
          expect(derived.to_s).to eq(v[:xprv])
        end

        it 'produces the expected xpub' do
          expect(derived.neuter.to_s).to eq(v[:xpub])
        end
      end
    end
  end

  # BIP-32 Test Vector 3 — tests leading-zero retention
  describe 'BIP-32 test vector 3' do
    let(:seed) do
      ['4b381541583be4423346c643850da4b320e46a87ae3d2a4e6da11eba819cd4acba45d239319ac14f863b8d5ab5a0d0c64d2e8a1e7d1457df2e5a3c51c73235be'].pack('H*')
    end
    let(:master) { described_class.from_seed(seed) }

    vectors = [
      {
        path: 'm',
        xpub: 'xpub661MyMwAqRbcEZVB4dScxMAdx6d4nFc9nvyvH3v4gJL378CSRZiYmhRoP7mBy6gSPSCYk6SzXPTf3ND1cZAceL7SfJ1Z3GC8vBgp2epUt13',
        xprv: 'xprv9s21ZrQH143K25QhxbucbDDuQ4naNntJRi4KUfWT7xo4EKsHt2QJDu7KXp1A3u7Bi1j8ph3EGsZ9Xvz9dGuVrtHHs7pXeTzjuxBrCmmhgC6'
      },
      {
        path: "m/0'",
        xpub: 'xpub68NZiKmJWnxxS6aaHmn81bvJeTESw724CRDs6HbuccFQN9Ku14VQrADWgqbhhTHBaohPX4CjNLf9fq9MYo6oDaPPLPxSb7gwQN3ih19Zm4Y',
        xprv: 'xprv9uPDJpEQgRQfDcW7BkF7eTya6RPxXeJCqCJGHuCJ4GiRVLzkTXBAJMu2qaMWPrS7AANYqdq6vcBcBUdJCVVFceUvJFjaPdGZ2y9WACViL4L'
      }
    ]

    vectors.each do |v|
      context "chain #{v[:path]}" do
        let(:derived) { v[:path] == 'm' ? master : master.derive_path(v[:path]) }

        it 'produces the expected xprv' do
          expect(derived.to_s).to eq(v[:xprv])
        end

        it 'produces the expected xpub' do
          expect(derived.neuter.to_s).to eq(v[:xpub])
        end
      end
    end
  end

  # BIP-32 Test Vector 4 — tests leading-zero retention
  describe 'BIP-32 test vector 4' do
    let(:seed) do
      ['3ddd5602285899a946114506157c7997e5444528f3003f6134712147db19b678'].pack('H*')
    end
    let(:master) { described_class.from_seed(seed) }

    vectors = [
      {
        path: 'm',
        xpub: 'xpub661MyMwAqRbcGczjuMoRm6dXaLDEhW1u34gKenbeYqAix21mdUKJyuyu5F1rzYGVxyL6tmgBUAEPrEz92mBXjByMRiJdba9wpnN37RLLAXa',
        xprv: 'xprv9s21ZrQH143K48vGoLGRPxgo2JNkJ3J3fqkirQC2zVdk5Dgd5w14S7fRDyHH4dWNHUgkvsvNDCkvAwcSHNAQwhwgNMgZhLtQC63zxwhQmRv'
      },
      {
        path: "m/0'",
        xpub: 'xpub69AUMk3qDBi3uW1sXgjCmVjJ2G6WQoYSnNHyzkmdCHEhSZ4tBok37xfFEqHd2AddP56Tqp4o56AePAgCjYdvpW2PU2jbUPFKsav5ut6Ch1m',
        xprv: 'xprv9vB7xEWwNp9kh1wQRfCCQMnZUEG21LpbR9NPCNN1dwhiZkjjeGRnaALmPXCX7SgjFTiCTT6bXes17boXtjq3xLpcDjzEuGLQBM5ohqkao9G'
      },
      {
        path: "m/0'/1'",
        xpub: 'xpub6BJA1jSqiukeaesWfxe6sNK9CCGaujFFSJLomWHprUL9DePQ4JDkM5d88n49sMGJxrhpjazuXYWdMf17C9T5XnxkopaeS7jGk1GyyVziaMt',
        xprv: 'xprv9xJocDuwtYCMNAo3Zw76WENQeAS6WGXQ55RCy7tDJ8oALr4FWkuVoHJeHVAcAqiZLE7Je3vZJHxspZdFHfnBEjHqU5hG1Jaj32dVoS6XLT1'
      }
    ]

    vectors.each do |v|
      context "chain #{v[:path]}" do
        let(:derived) { v[:path] == 'm' ? master : master.derive_path(v[:path]) }

        it 'produces the expected xprv' do
          expect(derived.to_s).to eq(v[:xprv])
        end

        it 'produces the expected xpub' do
          expect(derived.neuter.to_s).to eq(v[:xpub])
        end
      end
    end
  end

  describe '.from_seed' do
    it 'rejects seeds shorter than 16 bytes' do
      expect { described_class.from_seed("\x00" * 15) }.to raise_error(ArgumentError, /between 16 and 64/)
    end

    it 'rejects seeds longer than 64 bytes' do
      expect { described_class.from_seed("\x00" * 65) }.to raise_error(ArgumentError, /between 16 and 64/)
    end

    it 'creates a private key at depth 0' do
      seed = ['000102030405060708090a0b0c0d0e0f'].pack('H*')
      key = described_class.from_seed(seed)
      expect(key.depth).to eq(0)
      expect(key.private?).to be true
      expect(key.parent_fingerprint).to eq("\x00\x00\x00\x00".b)
      expect(key.child_number).to eq(0)
    end

    it 'supports testnet network' do
      seed = ['000102030405060708090a0b0c0d0e0f'].pack('H*')
      key = described_class.from_seed(seed, network: :testnet)
      expect(key.to_s).to start_with('tprv')
    end
  end

  describe '.from_string' do
    let(:seed) { ['000102030405060708090a0b0c0d0e0f'].pack('H*') }
    let(:master) { described_class.from_seed(seed) }

    it 'round-trips private keys' do
      xprv = master.to_s
      restored = described_class.from_string(xprv)
      expect(restored.to_s).to eq(xprv)
      expect(restored.private?).to be true
      expect(restored.depth).to eq(0)
    end

    it 'round-trips public keys' do
      xpub = master.neuter.to_s
      restored = described_class.from_string(xpub)
      expect(restored.to_s).to eq(xpub)
      expect(restored.public?).to be true
    end

    it 'rejects invalid checksum' do
      xprv = master.to_s
      # Corrupt a character
      corrupted = xprv[0...-2] + (xprv[-2] == 'a' ? 'b' : 'a') + xprv[-1]
      expect { described_class.from_string(corrupted) }.to raise_error(BSV::Primitives::Base58::ChecksumError)
    end

    it 'rejects version/key type mismatch' do
      # Build a payload with public version but private key data (0x00 prefix)
      pub_version = BSV::Primitives::ExtendedKey::VERSIONS[:mainnet_public]
      payload = [pub_version, ("\x00" * 9), ("\x00" * 32), "\x00", ("\x01" * 32)].join
      bad_string = BSV::Primitives::Base58.check_encode(payload)
      expect { described_class.from_string(bad_string) }
        .to raise_error(ArgumentError, /private key data with public version/)
    end
  end

  describe '#child' do
    let(:seed) { ['000102030405060708090a0b0c0d0e0f'].pack('H*') }
    let(:master) { described_class.from_seed(seed) }

    it 'raises on hardened derivation from public key' do
      pub = master.neuter
      expect { pub.child(described_class::HARDENED) }.to raise_error(ArgumentError, /cannot derive hardened/)
    end

    it 'raises when depth is 255' do
      # Build a key at depth 255
      key = described_class.new(
        key: master.key,
        chain_code: master.chain_code,
        version: master.version,
        depth: 255,
        parent_fingerprint: "\x00\x00\x00\x00".b,
        child_number: 0
      )
      expect { key.child(0) }.to raise_error(ArgumentError, /depth 255/)
    end

    it 'supports public child derivation' do
      # Derive public child from neutered key
      pub_master = master.neuter
      priv_child = master.child(0)

      pub_child_from_priv = priv_child.neuter
      pub_child_from_pub = pub_master.child(0)

      expect(pub_child_from_pub.to_s).to eq(pub_child_from_priv.to_s)
    end
  end

  describe '#derive_path' do
    let(:seed) { ['000102030405060708090a0b0c0d0e0f'].pack('H*') }
    let(:master) { described_class.from_seed(seed) }

    it 'raises if path does not start with m' do
      expect { master.derive_path('0/1') }.to raise_error(ArgumentError, /must start with 'm'/)
    end

    it 'produces the same result as step-by-step child calls' do
      path_derived = master.derive_path("m/0'/1/2'")
      step_derived = master.child(described_class::HARDENED).child(1).child(2 + described_class::HARDENED)
      expect(path_derived.to_s).to eq(step_derived.to_s)
    end

    it 'supports H suffix for hardened' do
      h_derived = master.derive_path('m/0H')
      tick_derived = master.derive_path("m/0'")
      expect(h_derived.to_s).to eq(tick_derived.to_s)
    end

    it 'returns the master key for path m' do
      expect(master.derive_path('m').to_s).to eq(master.to_s)
    end
  end

  describe '#neuter' do
    let(:seed) { ['000102030405060708090a0b0c0d0e0f'].pack('H*') }
    let(:master) { described_class.from_seed(seed) }

    it 'converts private to public' do
      pub = master.neuter
      expect(pub.public?).to be true
      expect(pub.private?).to be false
    end

    it 'preserves depth, parent fingerprint, and child number' do
      child = master.child(described_class::HARDENED)
      neutered = child.neuter
      expect(neutered.depth).to eq(child.depth)
      expect(neutered.parent_fingerprint).to eq(child.parent_fingerprint)
      expect(neutered.child_number).to eq(child.child_number)
    end

    it 'raises when called on a public key' do
      pub = master.neuter
      expect { pub.neuter }.to raise_error(ArgumentError, /already a public key/)
    end
  end

  describe '#private_key' do
    let(:seed) { ['000102030405060708090a0b0c0d0e0f'].pack('H*') }
    let(:master) { described_class.from_seed(seed) }

    it 'returns a PrivateKey instance' do
      pk = master.private_key
      expect(pk).to be_a(BSV::Primitives::PrivateKey)
    end

    it 'raises for public extended keys' do
      expect { master.neuter.private_key }.to raise_error(ArgumentError, /not a private/)
    end
  end

  describe '#public_key' do
    let(:seed) { ['000102030405060708090a0b0c0d0e0f'].pack('H*') }
    let(:master) { described_class.from_seed(seed) }

    it 'returns a PublicKey instance from private key' do
      pk = master.public_key
      expect(pk).to be_a(BSV::Primitives::PublicKey)
    end

    it 'returns a PublicKey instance from public key' do
      pk = master.neuter.public_key
      expect(pk).to be_a(BSV::Primitives::PublicKey)
    end

    it 'returns the same public key from private and neutered' do
      priv_pub = master.public_key
      neut_pub = master.neuter.public_key
      expect(priv_pub).to eq(neut_pub)
    end
  end

  describe '#fingerprint' do
    let(:seed) { ['000102030405060708090a0b0c0d0e0f'].pack('H*') }
    let(:master) { described_class.from_seed(seed) }

    it 'matches parent fingerprint of child' do
      child = master.child(described_class::HARDENED)
      expect(child.parent_fingerprint).to eq(master.fingerprint)
    end

    it 'preserves fingerprint chain across three generations' do
      child = master.child(described_class::HARDENED)
      grandchild = child.child(1)

      expect(child.parent_fingerprint).to eq(master.fingerprint)
      expect(grandchild.parent_fingerprint).to eq(child.fingerprint)
      expect(grandchild.parent_fingerprint).not_to eq(master.fingerprint)
    end

    it 'is 4 bytes' do
      expect(master.fingerprint.length).to eq(4)
    end
  end

  describe '#identifier' do
    let(:seed) { ['000102030405060708090a0b0c0d0e0f'].pack('H*') }
    let(:master) { described_class.from_seed(seed) }

    it 'is 20 bytes (Hash160)' do
      expect(master.identifier.length).to eq(20)
    end
  end
end
