# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

BEEF_PARTY_VECTORS = YAML.load_file(
  File.join(__dir__, '../../fixtures/beef_party_vectors.yml')
).freeze

RSpec.describe BSV::Transaction::BeefParty do
  let(:proven_wtxid) do
    [BEEF_PARTY_VECTORS['proven_dtxid']].pack('H*').reverse
  end

  let(:spend_wtxid) do
    [BEEF_PARTY_VECTORS['spend_dtxid']].pack('H*').reverse
  end

  let(:input_beef) do
    BSV::Transaction::Beef.from_hex(BEEF_PARTY_VECTORS['input_beef_hex'])
  end

  describe 'general' do
    it 'subclasses Beef' do
      expect(described_class.superclass).to eq(BSV::Transaction::Beef)
    end
  end

  describe '#initialize' do
    it 'starts with no parties when called with no args' do
      bp = described_class.new
      expect(bp.party?('alice')).to be(false)
    end

    it 'accepts an initial parties array' do
      bp = described_class.new(%w[alice bob])
      expect(bp.party?('alice')).to be(true)
      expect(bp.party?('bob')).to be(true)
    end

    it 'raises on duplicate parties in the initial list' do
      expect { described_class.new(%w[alice alice]) }.to raise_error(ArgumentError)
    end
  end

  describe '#party? / #add_party' do
    subject(:bp) { described_class.new }

    it 'reports false for unknown parties' do
      expect(bp.party?('alice')).to be(false)
    end

    it 'reports true after add_party' do
      bp.add_party('alice')
      expect(bp.party?('alice')).to be(true)
    end

    it 'raises ArgumentError on duplicate add_party' do
      bp.add_party('alice')
      expect { bp.add_party('alice') }.to raise_error(ArgumentError)
    end
  end

  describe '#add_known_wtxids_for_party' do
    subject(:bp) { described_class.new(['alice']) }

    it 'records wtxids against a known party' do
      bp.add_known_wtxids_for_party('alice', [proven_wtxid])
      expect(bp.known_wtxids_for_party('alice')).to include(proven_wtxid)
    end

    it 'auto-creates an unknown party (TS parity)' do
      expect(bp.party?('carol')).to be(false)
      bp.add_known_wtxids_for_party('carol', [proven_wtxid])
      expect(bp.party?('carol')).to be(true)
    end

    it 'rejects malformed wtxids (hex string instead of binary)' do
      expect do
        bp.add_known_wtxids_for_party('alice', [BEEF_PARTY_VECTORS['proven_dtxid']])
      end.to raise_error(ArgumentError)
    end

    it 'is idempotent — adding the same wtxid twice does not double-count' do
      bp.add_known_wtxids_for_party('alice', [proven_wtxid])
      bp.add_known_wtxids_for_party('alice', [proven_wtxid])
      count = bp.known_wtxids_for_party('alice').count { |w| w == proven_wtxid }
      expect(count).to eq(1)
    end

    it 'merges TXID-only entries into the underlying BEEF' do
      bp.add_known_wtxids_for_party('alice', [proven_wtxid])
      entry = bp.transactions.find { |bt| bt.wtxid == proven_wtxid }
      expect(entry).not_to be_nil
    end

    it 'does not downgrade an existing stronger entry to TXID-only' do
      bp.merge(input_beef)
      # proven_wtxid is a TXID-only in input_beef; merged as TXID-only
      bp.add_known_wtxids_for_party('alice', [proven_wtxid])
      entry = bp.transactions.find { |bt| bt.wtxid == proven_wtxid }
      # It was TxidOnly in input_beef — merging keeps it as TxidOnly; add_known... does not change it
      expect(entry).to be_a(BSV::Transaction::Beef::TxidOnlyEntry)
    end
  end

  describe '#known_wtxids_for_party' do
    subject(:bp) { described_class.new(['alice']) }

    it 'returns the recorded wtxids' do
      bp.add_known_wtxids_for_party('alice', [proven_wtxid])
      expect(bp.known_wtxids_for_party('alice')).to eq([proven_wtxid])
    end

    it 'raises ArgumentError on unknown party' do
      expect { bp.known_wtxids_for_party('carol') }.to raise_error(ArgumentError)
    end
  end

  describe '#trimmed_beef_for_party' do
    subject(:bp) do
      party = described_class.new(%w[alice bob])
      party.merge(input_beef)
      party.add_known_wtxids_for_party('alice', [proven_wtxid])
      party
    end

    it 'returns a new Beef (not a BeefParty)' do
      result = bp.trimmed_beef_for_party('alice')
      expect(result).to be_a(BSV::Transaction::Beef)
      expect(result).not_to be_a(described_class)
    end

    it 'does not mutate self' do
      original_count = bp.transactions.length
      bp.trimmed_beef_for_party('alice')
      expect(bp.transactions.length).to eq(original_count)
    end

    it 'drops TXID-only entries known to the party' do
      result = bp.trimmed_beef_for_party('alice')
      expect(result.transactions.none? { |bt| bt.wtxid == proven_wtxid }).to be(true)
    end

    it 'retains RawTxEntry even when the party knows the txid' do
      bp.add_known_wtxids_for_party('alice', [spend_wtxid])
      result = bp.trimmed_beef_for_party('alice')
      entry = result.transactions.find { |bt| bt.wtxid == spend_wtxid }
      # spend_wtxid entry is a RawTxEntry — not trimmed
      expect(entry).to be_a(BSV::Transaction::Beef::RawTxEntry)
    end

    it 'returns a no-op trim for a party that knows nothing' do
      result = bp.trimmed_beef_for_party('bob')
      expect(result.transactions.length).to eq(bp.transactions.length)
    end

    it 'raises ArgumentError for an unknown party' do
      expect { bp.trimmed_beef_for_party('carol') }.to raise_error(ArgumentError)
    end

    it 'preserves @subject_wtxid for Atomic BEEF' do
      subject_wtxid = "\xFF".b * 32
      bp.instance_variable_set(:@subject_wtxid, subject_wtxid)
      result = bp.trimmed_beef_for_party('alice')
      expect(result.instance_variable_get(:@subject_wtxid)).to eq(subject_wtxid)
    end
  end

  describe '#merge_beef_from_party' do
    subject(:bp) { described_class.new(%w[alice bob]) }

    it 'accepts a Beef instance' do
      bp.merge_beef_from_party('alice', input_beef)
      expect(bp.party?('alice')).to be(true)
    end

    it 'accepts a binary BEEF blob' do
      binary = [BEEF_PARTY_VECTORS['input_beef_hex']].pack('H*')
      bp.merge_beef_from_party('bob', binary)
      expect(bp.party?('bob')).to be(true)
    end

    it 'records the valid wtxids of the merged BEEF as known to the party' do
      # input_beef has spend_tx as RawTxEntry; its inputs chain to the TXID-only proven_tx
      # but proven_tx is TXID-only — not a proven or resolved tx, so valid_wtxids
      # for input_beef depends on whether proven_tx's inputs are available
      # For the input_beef (no bumps, proven_tx as TXID-only) valid_wtxids may be empty.
      # Use a BEEF with a real ProvenTxEntry instead:
      brc62_hex = '0100beef01fe636d0c0007021400fe507c0c7aa754cef1f7889d5fd395cf1f785dd7de98eed895dbedfe4e5bc70d' \
                  '1502ac4e164f5bc16746bb0868404292ac8318bbac3800e4aad13a014da427adce3e010b00bc4ff395efd11719b2' \
                  '77694cface5aa50d085a0bb81f613f70313acd28cf4557010400574b2d9142b8d28b61d88e3b2c3f44d858411356' \
                  'b49a28a4643b6d1a6a092a5201030051a05fc84d531b5d250c23f4f886f6812f9fe3f402d61607f977b4ecd2701c' \
                  '19010000fd781529d58fc2523cf396a7f25440b409857e7e221766c57214b1d38c7b481f01010062f542f45ea366' \
                  '0f86c013ced80534cb5fd4c19d66c56e7e8c5d4bf2d40acc5e010100b121e91836fd7cd5102b654e9f72f3cf6fdb' \
                  'fd0b161c53a9c54b12c841126331020100000001cd4e4cac3c7b56920d1e7655e7e260d31f29d9a388d04910f1bb' \
                  'd72304a79029010000006b483045022100e75279a205a547c445719420aa3138bf14743e3f42618e5f86a19bde14bb' \
                  '95f7022064777d34776b05d816daf1699493fcdf2ef5a5ab1ad710d9c97bfb5b8f7cef3641210263e2dee22b1ddc' \
                  '5e11f6fab8bcd2378bdd19580d640501ea956ec0e786f93e76ffffffff013e660000000000001976a9146bfd5c7f' \
                  'be21529d45803dbcf0c87dd3c71efbc288ac0000000001000100000001ac4e164f5bc16746bb0868404292ac8318' \
                  'bbac3800e4aad13a014da427adce3e000000006a47304402203a61a2e931612b4bda08d541cfb980885173b8dcf6' \
                  '4a3471238ae7abcd368d6402204cbf24f04b9aa2256d8901f0ed97866603d2be8324c2bfb7a37bf8fc90edd5b441' \
                  '210263e2dee22b1ddc5e11f6fab8bcd2378bdd19580d640501ea956ec0e786f93e76ffffffff013c660000000000' \
                  '001976a9146bfd5c7fbe21529d45803dbcf0c87dd3c71efbc288ac0000000000'
      full_beef = BSV::Transaction::Beef.from_hex(brc62_hex)
      bp.merge_beef_from_party('alice', full_beef)
      known = bp.known_wtxids_for_party('alice')
      expect(known).not_to be_empty
    end

    it 'auto-creates the party when unknown' do
      expect(bp.party?('carol')).to be(false)
      bp.merge_beef_from_party('carol', input_beef)
      expect(bp.party?('carol')).to be(true)
    end
  end

  describe 'cross-SDK conformance' do
    it 'produces the same trimmed BEEF binary as the TS SDK (alice trim)' do
      bp = described_class.new(%w[alice bob])
      bp.merge(input_beef)
      bp.add_known_wtxids_for_party('alice', [proven_wtxid])

      result = bp.trimmed_beef_for_party('alice')
      expect(result.to_hex).to eq(BEEF_PARTY_VECTORS['trimmed_for_alice_hex'])
    end

    it 'produces the same trimmed BEEF binary as the TS SDK (bob no-op trim)' do
      bp = described_class.new(%w[alice bob])
      bp.merge(input_beef)
      bp.add_known_wtxids_for_party('alice', [proven_wtxid])

      result = bp.trimmed_beef_for_party('bob')
      expect(result.to_hex).to eq(BEEF_PARTY_VECTORS['trimmed_for_bob_hex'])
    end
  end
end
