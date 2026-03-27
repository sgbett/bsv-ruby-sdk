# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::Validators do
  describe '.validate_protocol_id!' do
    it 'accepts valid protocol IDs at each security level' do
      expect { described_class.validate_protocol_id!([0, 'hello world']) }.not_to raise_error
      expect { described_class.validate_protocol_id!([1, 'test protocol name']) }.not_to raise_error
      expect { described_class.validate_protocol_id!([2, 'abcde']) }.not_to raise_error
    end

    it 'rejects security level 3' do
      expect { described_class.validate_protocol_id!([3, 'hello world']) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects negative security levels' do
      expect { described_class.validate_protocol_id!([-1, 'hello world']) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names shorter than 5 characters' do
      expect { described_class.validate_protocol_id!([0, 'abcd']) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names longer than 400 characters' do
      expect { described_class.validate_protocol_id!([0, 'a' * 401]) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names with uppercase letters' do
      expect { described_class.validate_protocol_id!([0, 'Hello World']) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names with consecutive spaces' do
      expect { described_class.validate_protocol_id!([0, 'hello  world']) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names ending with " protocol"' do
      expect { described_class.validate_protocol_id!([0, 'hello protocol']) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names starting with "admin"' do
      expect { described_class.validate_protocol_id!([0, 'admin secret']) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names starting with "p "' do
      expect { described_class.validate_protocol_id!([0, 'p reserved thing']) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects non-array values' do
      expect { described_class.validate_protocol_id!('hello') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects arrays with wrong length' do
      expect { described_class.validate_protocol_id!([0]) }.to raise_error(BSV::Wallet::InvalidParameterError)
      expect { described_class.validate_protocol_id!([0, 'hello', 'extra']) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'allows up to 430 chars for specific linkage revelation protocol' do
      # The 430-char limit only applies when the name starts with 'specific linkage revelation'
      name = "specific linkage revelation #{'a' * 402}"
      expect(name.length).to eq(430)
      expect { described_class.validate_protocol_id!([0, name]) }.not_to raise_error
    end

    it 'rejects "specific linkage revelation" names over 430 chars' do
      name = "specific linkage revelation #{'a' * 403}"
      expect { described_class.validate_protocol_id!([0, name]) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe '.validate_key_id!' do
    it 'accepts a single-character key ID' do
      expect { described_class.validate_key_id!('1') }.not_to raise_error
    end

    it 'accepts a key ID at the 800-byte limit' do
      expect { described_class.validate_key_id!('a' * 800) }.not_to raise_error
    end

    it 'rejects an empty key ID' do
      expect { described_class.validate_key_id!('') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects key IDs over 800 bytes' do
      expect { described_class.validate_key_id!('a' * 801) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects non-string values' do
      expect { described_class.validate_key_id!(42) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe '.validate_counterparty!' do
    it 'accepts "self"' do
      expect { described_class.validate_counterparty!('self') }.not_to raise_error
    end

    it 'accepts "anyone"' do
      expect { described_class.validate_counterparty!('anyone') }.not_to raise_error
    end

    it 'accepts a valid 66-char hex compressed public key' do
      key = BSV::Primitives::PrivateKey.generate.public_key.to_hex
      expect { described_class.validate_counterparty!(key) }.not_to raise_error
    end

    it 'rejects an arbitrary short string' do
      expect { described_class.validate_counterparty!('invalid') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects a hex string that is not 66 characters' do
      expect { described_class.validate_counterparty!('abcd1234') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects a 66-char string with non-hex characters' do
      expect { described_class.validate_counterparty!('g' * 66) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe '.validate_description!' do
    it 'accepts a 5-character description' do
      expect { described_class.validate_description!('hello') }.not_to raise_error
    end

    it 'accepts a 50-character description' do
      expect { described_class.validate_description!('a' * 50) }.not_to raise_error
    end

    it 'rejects a description under 5 characters' do
      expect { described_class.validate_description!('abcd') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects a description over 50 characters' do
      expect { described_class.validate_description!('a' * 51) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'accepts a custom parameter name in the error' do
      expect { described_class.validate_description!('x', 'my_desc') }.to raise_error(BSV::Wallet::InvalidParameterError, /my_desc/)
    end
  end

  describe '.validate_basket!' do
    it 'accepts a valid basket name' do
      expect { described_class.validate_basket!('my tokens') }.not_to raise_error
    end

    it 'accepts a name at the minimum length' do
      expect { described_class.validate_basket!('token') }.not_to raise_error
    end

    it 'rejects names under 5 characters' do
      expect { described_class.validate_basket!('abcd') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names over 300 characters' do
      expect { described_class.validate_basket!('a' * 301) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names starting with "admin"' do
      expect { described_class.validate_basket!('admin tokens') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects the reserved name "default"' do
      expect { described_class.validate_basket!('default') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names ending with " basket"' do
      expect { described_class.validate_basket!('token basket') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects names starting with "p "' do
      expect { described_class.validate_basket!('p reserved') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects consecutive spaces' do
      expect { described_class.validate_basket!('my  tokens') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects uppercase letters' do
      expect { described_class.validate_basket!('My Tokens') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe '.validate_label!' do
    it 'accepts a single-character label' do
      expect { described_class.validate_label!('x') }.not_to raise_error
    end

    it 'accepts a label at the 300-character limit' do
      expect { described_class.validate_label!('a' * 300) }.not_to raise_error
    end

    it 'rejects an empty label' do
      expect { described_class.validate_label!('') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects labels over 300 characters' do
      expect { described_class.validate_label!('a' * 301) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe '.validate_tag!' do
    it 'accepts a single-character tag' do
      expect { described_class.validate_tag!('x') }.not_to raise_error
    end

    it 'accepts a tag at the 300-character limit' do
      expect { described_class.validate_tag!('a' * 300) }.not_to raise_error
    end

    it 'rejects an empty tag' do
      expect { described_class.validate_tag!('') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects tags over 300 characters' do
      expect { described_class.validate_tag!('a' * 301) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe '.validate_outpoint!' do
    let(:valid_txid) { 'a' * 64 }

    it 'accepts a zero-index outpoint' do
      expect { described_class.validate_outpoint!("#{valid_txid}.0") }.not_to raise_error
    end

    it 'accepts a multi-digit index outpoint' do
      expect { described_class.validate_outpoint!("#{valid_txid}.42") }.not_to raise_error
    end

    it 'rejects a string without a dot separator' do
      expect { described_class.validate_outpoint!('abcdef') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects an outpoint with a txid shorter than 64 hex chars' do
      expect { described_class.validate_outpoint!('short.0') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects an outpoint with a non-numeric index' do
      expect { described_class.validate_outpoint!("#{valid_txid}.abc") }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects an outpoint with a negative index' do
      expect { described_class.validate_outpoint!("#{valid_txid}.-1") }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects a txid with uppercase hex characters' do
      txid = 'A' * 64
      expect { described_class.validate_outpoint!("#{txid}.0") }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe '.validate_satoshis!' do
    it 'accepts 1 satoshi' do
      expect { described_class.validate_satoshis!(1) }.not_to raise_error
    end

    it 'accepts the maximum supply of 21 million BSV in satoshis' do
      expect { described_class.validate_satoshis!(2_100_000_000_000_000) }.not_to raise_error
    end

    it 'rejects zero' do
      expect { described_class.validate_satoshis!(0) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects values above the maximum supply' do
      expect { described_class.validate_satoshis!(2_100_000_000_000_001) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects negative values' do
      expect { described_class.validate_satoshis!(-1) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects non-integer values' do
      expect { described_class.validate_satoshis!(1.5) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'accepts a custom parameter name in the error' do
      expect { described_class.validate_satoshis!(0, 'output_satoshis') }.to raise_error(BSV::Wallet::InvalidParameterError, /output_satoshis/)
    end
  end

  describe '.validate_pub_key_hex!' do
    it 'accepts a valid 66-character compressed public key hex string' do
      key = BSV::Primitives::PrivateKey.generate.public_key.to_hex
      expect { described_class.validate_pub_key_hex!(key) }.not_to raise_error
    end

    it 'rejects a string with non-hex characters' do
      expect { described_class.validate_pub_key_hex!('not hex at all!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects a hex string that is not 66 characters' do
      expect { described_class.validate_pub_key_hex!('abcdef') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects a 64-character hex string (uncompressed key prefix length)' do
      expect { described_class.validate_pub_key_hex!('a' * 64) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'accepts a custom parameter name in the error' do
      expect { described_class.validate_pub_key_hex!('short', 'verifier') }.to raise_error(BSV::Wallet::InvalidParameterError, /verifier/)
    end
  end

  describe '.validate_hex_string!' do
    it 'accepts an empty string' do
      expect { described_class.validate_hex_string!('') }.not_to raise_error
    end

    it 'accepts a valid even-length hex string' do
      expect { described_class.validate_hex_string!('deadbeef') }.not_to raise_error
    end

    it 'rejects an odd-length hex string' do
      expect { described_class.validate_hex_string!('abc') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects a string with non-hex characters' do
      expect { described_class.validate_hex_string!('nothex!!') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe '.validate_integer!' do
    it 'accepts a valid integer' do
      expect { described_class.validate_integer!(5, 'count') }.not_to raise_error
    end

    it 'accepts an integer at the minimum bound' do
      expect { described_class.validate_integer!(0, 'offset', min: 0) }.not_to raise_error
    end

    it 'accepts an integer at the maximum bound' do
      expect { described_class.validate_integer!(10, 'limit', max: 10) }.not_to raise_error
    end

    it 'rejects an integer below the minimum' do
      expect { described_class.validate_integer!(-1, 'offset', min: 0) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects an integer above the maximum' do
      expect { described_class.validate_integer!(11, 'limit', max: 10) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'rejects a non-integer value' do
      expect { described_class.validate_integer!('five', 'count') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end
end
