# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Wallet::Wire::Validation do
  def expect_invalid(name, &block)
    expect(&block).to raise_error(BSV::Wallet::InvalidParameterError) do |e|
      expect(e.message).to include(name)
    end
  end

  # --- hex_string! ---

  describe '.hex_string!' do
    it 'accepts a valid lowercase hex string' do
      expect { described_class.hex_string!('pubkey', "02#{'a' * 64}") }.not_to raise_error
    end

    it 'accepts an uppercase hex string' do
      expect { described_class.hex_string!('v', "02#{'A' * 64}") }.not_to raise_error
    end

    it 'accepts an empty string' do
      expect { described_class.hex_string!('data', '') }.not_to raise_error
    end

    it 'rejects an odd-length hex string' do
      expect_invalid('pubkey') { described_class.hex_string!('pubkey', '02xx') }
    end

    it 'rejects non-hex characters' do
      expect_invalid('pubkey') { described_class.hex_string!('pubkey', 'gg') }
    end

    it 'accepts when length matches' do
      expect { described_class.hex_string!('sig', 'aa' * 33, length: 66) }.not_to raise_error
    end

    it 'rejects when length does not match' do
      expect_invalid('sig') { described_class.hex_string!('sig', 'aa' * 34, length: 66) }
    end
  end

  # --- outpoint_string! ---

  describe '.outpoint_string!' do
    let(:valid_txid) { 'a' * 64 }

    it 'accepts a valid outpoint' do
      expect { described_class.outpoint_string!('outpoint', "#{valid_txid}.0") }.not_to raise_error
    end

    it 'accepts the max uint32 vout' do
      expect { described_class.outpoint_string!('outpoint', "#{valid_txid}.4294967295") }.not_to raise_error
    end

    it 'rejects vout that overflows uint32' do
      expect_invalid('outpoint') do
        described_class.outpoint_string!('outpoint', "#{valid_txid}.4294967296")
      end
    end

    it 'rejects a txid shorter than 64 hex chars' do
      expect_invalid('outpoint') { described_class.outpoint_string!('outpoint', 'abc.0') }
    end

    it 'rejects missing dot separator' do
      expect_invalid('outpoint') { described_class.outpoint_string!('outpoint', valid_txid) }
    end

    it 'rejects non-numeric vout' do
      expect_invalid('outpoint') { described_class.outpoint_string!('outpoint', "#{valid_txid}.abc") }
    end
  end

  # --- pub_key_hex! ---

  describe '.pub_key_hex!' do
    it 'accepts a 66-char 02-prefixed pubkey' do
      expect { described_class.pub_key_hex!('pk', "02#{'a' * 64}") }.not_to raise_error
    end

    it 'accepts a 66-char 03-prefixed pubkey' do
      expect { described_class.pub_key_hex!('pk', "03#{'b' * 64}") }.not_to raise_error
    end

    it 'rejects wrong prefix 04' do
      expect_invalid('pk') { described_class.pub_key_hex!('pk', "04#{'a' * 64}") }
    end

    it 'rejects short hex' do
      expect_invalid('pk') { described_class.pub_key_hex!('pk', "02#{'a' * 62}") }
    end

    it 'rejects non-hex characters' do
      expect_invalid('pk') { described_class.pub_key_hex!('pk', '02xx') }
    end

    it 'rejects non-string' do
      expect_invalid('pk') { described_class.pub_key_hex!('pk', 123) }
    end
  end

  # --- wallet_counterparty! ---

  describe '.wallet_counterparty!' do
    it 'accepts "self"' do
      expect { described_class.wallet_counterparty!('cp', 'self') }.not_to raise_error
    end

    it 'accepts "anyone"' do
      expect { described_class.wallet_counterparty!('cp', 'anyone') }.not_to raise_error
    end

    it 'accepts a 66-char hex pubkey starting with 02' do
      expect { described_class.wallet_counterparty!('cp', "02#{'a' * 64}") }.not_to raise_error
    end

    it 'accepts a 66-char hex pubkey starting with 03' do
      expect { described_class.wallet_counterparty!('cp', "03#{'f' * 64}") }.not_to raise_error
    end

    it 'rejects an arbitrary string' do
      expect_invalid('cp') { described_class.wallet_counterparty!('cp', 'not-valid') }
    end

    it 'rejects a 66-char pubkey with 04 prefix' do
      expect_invalid('cp') { described_class.wallet_counterparty!('cp', "04#{'a' * 64}") }
    end
  end

  # --- wallet_protocol! ---

  describe '.wallet_protocol!' do
    it 'accepts [2, "hello world"]' do
      expect { described_class.wallet_protocol!('proto', [2, 'hello world']) }.not_to raise_error
    end

    it 'accepts [0, "basic protocol"]' do
      expect { described_class.wallet_protocol!('proto', [0, 'basic protocol']) }.not_to raise_error
    end

    it 'rejects security level out of range' do
      expect_invalid('proto') { described_class.wallet_protocol!('proto', [3, 'hello world']) }
    end

    it 'rejects protocol name too short' do
      expect_invalid('proto') { described_class.wallet_protocol!('proto', [2, 'ab']) }
    end

    it 'accepts uppercase protocol name (normalised to lowercase)' do
      expect { described_class.wallet_protocol!('proto', [2, 'HELLO WORLD']) }.not_to raise_error
    end

    it 'rejects consecutive spaces in protocol name' do
      expect_invalid('proto') { described_class.wallet_protocol!('proto', [2, 'a  b c d e']) }
    end

    it 'rejects non-array input' do
      expect_invalid('proto') { described_class.wallet_protocol!('proto', 'hello world') }
    end
  end

  # --- satoshi_value! ---

  describe '.satoshi_value!' do
    it 'accepts 0' do
      expect { described_class.satoshi_value!('amount', 0) }.not_to raise_error
    end

    it 'accepts a valid amount' do
      expect { described_class.satoshi_value!('amount', 1000) }.not_to raise_error
    end

    it 'accepts max supply' do
      expect { described_class.satoshi_value!('amount', 21_000_000 * (10**8)) }.not_to raise_error
    end

    it 'rejects negative values' do
      expect_invalid('amount') { described_class.satoshi_value!('amount', -1) }
    end

    it 'rejects values exceeding max supply' do
      expect_invalid('amount') { described_class.satoshi_value!('amount', (21_000_000 * (10**8)) + 1) }
    end

    it 'rejects non-integer' do
      expect_invalid('amount') { described_class.satoshi_value!('amount', 1.5) }
    end
  end

  # --- originator_domain! ---

  describe '.originator_domain!' do
    it 'accepts a normal domain' do
      expect { described_class.originator_domain!('originator', 'app.example.com') }.not_to raise_error
    end

    it 'accepts a 250-byte string' do
      expect { described_class.originator_domain!('originator', 'x' * 250) }.not_to raise_error
    end

    it 'rejects a 251-byte string' do
      expect_invalid('originator') { described_class.originator_domain!('originator', 'x' * 251) }
    end

    it 'measures length in bytes (UTF-8 multi-byte)' do
      # 2-byte char × 125 = 250 bytes → allowed
      expect { described_class.originator_domain!('originator', "\xC3\xA9" * 125) }.not_to raise_error
      # 2-byte char × 126 = 252 bytes → rejected
      expect_invalid('originator') { described_class.originator_domain!('originator', "\xC3\xA9" * 126) }
    end
  end

  # --- key_id_string_1_to_800! ---

  describe '.key_id_string_1_to_800!' do
    it 'accepts a normal key ID' do
      expect { described_class.key_id_string_1_to_800!('key_id', 'key-1') }.not_to raise_error
    end

    it 'accepts a single character' do
      expect { described_class.key_id_string_1_to_800!('key_id', 'x') }.not_to raise_error
    end

    it 'accepts 800 bytes' do
      expect { described_class.key_id_string_1_to_800!('key_id', 'x' * 800) }.not_to raise_error
    end

    it 'rejects empty string' do
      expect_invalid('key_id') { described_class.key_id_string_1_to_800!('key_id', '') }
    end

    it 'rejects 801 bytes' do
      expect_invalid('key_id') { described_class.key_id_string_1_to_800!('key_id', 'x' * 801) }
    end
  end

  # --- acquisition_protocol! ---

  describe '.acquisition_protocol!' do
    it 'accepts "direct"' do
      expect { described_class.acquisition_protocol!('proto', 'direct') }.not_to raise_error
    end

    it 'accepts "issuance"' do
      expect { described_class.acquisition_protocol!('proto', 'issuance') }.not_to raise_error
    end

    it 'rejects anything else' do
      expect_invalid('proto') { described_class.acquisition_protocol!('proto', 'other') }
    end
  end

  # --- ProtoWallet::Validators delegation ---

  describe 'BSV::Wallet::ProtoWallet::Validators delegates to Wire::Validation' do
    let(:validators) { BSV::Wallet::ProtoWallet::Validators }

    it 'validate_protocol_id! delegates and accepts valid input' do
      expect { validators.validate_protocol_id!([1, 'test protocol']) }.not_to raise_error
    end

    it 'validate_protocol_id! delegates and rejects invalid input' do
      expect { validators.validate_protocol_id!([3, 'test protocol']) }
        .to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'validate_key_id! delegates and accepts valid input' do
      expect { validators.validate_key_id!('key-1') }.not_to raise_error
    end

    it 'validate_key_id! delegates and rejects empty string' do
      expect { validators.validate_key_id!('') }
        .to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'validate_counterparty! delegates and accepts "self"' do
      expect { validators.validate_counterparty!('self') }.not_to raise_error
    end

    it 'validate_counterparty! delegates and accepts a valid pubkey' do
      expect { validators.validate_counterparty!("02#{'a' * 64}") }.not_to raise_error
    end

    it 'validate_counterparty! delegates and rejects invalid input' do
      expect { validators.validate_counterparty!('not-valid') }
        .to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'validate_pub_key_hex! delegates and accepts a valid pubkey' do
      expect { validators.validate_pub_key_hex!("02#{'a' * 64}") }.not_to raise_error
    end

    it 'validate_pub_key_hex! delegates and rejects short key' do
      expect { validators.validate_pub_key_hex!("02#{'a' * 62}") }
        .to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end
end
