# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Overlay::Historian do
  # Counter to ensure each make_tx call produces a unique transaction hash.
  let(:tx_counter) { [0] }
  # Interpreter that returns the output index as the value for every output.
  let(:index_interpreter) { ->(_tx, idx, _ctx) { idx } }
  # Interpreter that always returns nil.
  let(:nil_interpreter) { ->(_tx, _idx, _ctx) {} }

  # Builds a minimal Tx with a unique satoshi value so no two calls produce the same hash.
  def make_tx(output_count: 1, wtxid: nil)
    tx = BSV::Transaction::Tx.new
    unique_sats = (tx_counter[0] += 1) * 1000
    output_count.times do |i|
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: unique_sats + i,
                      locking_script: BSV::Script::Script.new
                    ))
    end
    # Override wtxid by stubbing when a specific value is needed for cycle tests.
    allow(tx).to receive(:wtxid).and_return(wtxid) if wtxid
    tx
  end

  # Attaches +source_tx+ as the source_transaction of a new input on +tx+.
  def wire_input(tx, source_tx)
    input = BSV::Transaction::TransactionInput.new(
      prev_wtxid: source_tx.wtxid,
      prev_tx_out_index: 0
    )
    input.source_transaction = source_tx
    tx.add_input(input)
  end

  describe '#build_history' do
    context 'with no interpretable outputs' do
      it 'returns an empty array' do
        tx = make_tx
        historian = described_class.new(nil_interpreter)
        expect(historian.build_history(tx)).to eq([])
      end
    end

    context 'with one interpretable output' do
      it 'returns that single value' do
        tx = make_tx(output_count: 1)
        historian = described_class.new(index_interpreter)
        expect(historian.build_history(tx)).to eq([0])
      end
    end

    context 'with chained transactions tx1 <- tx2 <- tx3' do
      it 'returns values in chronological order (oldest first)' do
        tx1 = make_tx
        tx2 = make_tx
        tx3 = make_tx

        # Use compare_by_identity so distinct Tx objects with the same content are keyed separately.
        labels = {}.compare_by_identity
        labels[tx1] = 'tx1'
        labels[tx2] = 'tx2'
        labels[tx3] = 'tx3'

        labelling_interpreter = lambda do |tx, idx, _ctx|
          idx.zero? ? labels[tx] : nil
        end

        wire_input(tx2, tx1)
        wire_input(tx3, tx2)

        historian = described_class.new(labelling_interpreter)
        expect(historian.build_history(tx3)).to eq(%w[tx1 tx2 tx3])
      end
    end

    context 'with multiple inputs per transaction' do
      it 'walks all input branches' do
        visited_tx_ids = []
        tracking_interpreter = lambda do |tx, idx, _ctx|
          return nil unless idx.zero?

          visited_tx_ids << tx.dtxid_hex
          tx.dtxid_hex
        end

        tx1 = make_tx
        tx2 = make_tx
        tx3 = make_tx

        wire_input(tx3, tx1)
        wire_input(tx3, tx2)

        historian = described_class.new(tracking_interpreter)
        result = historian.build_history(tx3)

        expect(result.length).to eq(3)
        expect(result).to include(tx1.dtxid_hex, tx2.dtxid_hex, tx3.dtxid_hex)
      end
    end

    context 'with circular reference' do
      it 'does not infinite-loop and visits each tx once' do
        # Use binary wtxid stubs so the visited set works correctly.
        wtxid1 = "\x01" * 32
        wtxid2 = "\x02" * 32

        tx1 = make_tx(wtxid: wtxid1)
        tx2 = make_tx(wtxid: wtxid2)

        input1 = BSV::Transaction::TransactionInput.new(prev_wtxid: wtxid2, prev_tx_out_index: 0)
        input1.source_transaction = tx2
        allow(tx1).to receive(:inputs).and_return([input1])

        input2 = BSV::Transaction::TransactionInput.new(prev_wtxid: wtxid1, prev_tx_out_index: 0)
        input2.source_transaction = tx1
        allow(tx2).to receive(:inputs).and_return([input2])

        historian = described_class.new(index_interpreter)
        result = historian.build_history(tx2)

        expect(result.length).to eq(2)
      end
    end

    context 'when interpreter raises' do
      it 'swallows the exception and continues traversal' do
        raising_interpreter = lambda do |_tx, idx, _ctx|
          raise 'boom' if idx.zero?

          idx
        end

        tx = make_tx(output_count: 3)
        historian = described_class.new(raising_interpreter)
        result = historian.build_history(tx)

        # Outputs 1 and 2 succeed; after reverse, order is [2, 1].
        expect(result).to eq([2, 1])
      end
    end

    context 'when interpreter returns falsy non-nil values' do
      it 'includes false, 0, and empty string in history' do
        falsy_interpreter = lambda do |_tx, idx, _ctx|
          case idx
          when 0 then false
          when 1 then 0
          when 2 then ''
          end
        end

        tx = make_tx(output_count: 3)
        historian = described_class.new(falsy_interpreter)
        result = historian.build_history(tx)

        # Accumulated as [false, 0, ''] then reversed to ['', 0, false].
        expect(result).to eq(['', 0, false])
      end
    end

    context 'when input has no source_transaction' do
      it 'skips that input without raising' do
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: BSV::Primitives::Digest.sha256d('dummy'),
          prev_tx_out_index: 0
        )
        # source_transaction is nil by default

        tx = make_tx
        allow(tx).to receive(:inputs).and_return([input])

        historian = described_class.new(index_interpreter)
        expect(historian.build_history(tx)).to eq([0])
      end
    end
  end

  describe 'caching' do
    let(:cache) { {} }

    it 'populates the cache on first call' do
      tx = make_tx
      historian = described_class.new(index_interpreter, history_cache: cache)
      historian.build_history(tx)
      expect(cache.size).to eq(1)
    end

    it 'returns equal but not identical array on cache hit' do
      tx = make_tx
      historian = described_class.new(index_interpreter, history_cache: cache)
      result1 = historian.build_history(tx)
      result2 = historian.build_history(tx)

      expect(result1).to eq(result2)
      expect(result1).not_to be(result2)
    end

    it 'invalidates when interpreter_version differs' do
      tx = make_tx
      h1 = described_class.new(index_interpreter, history_cache: cache, interpreter_version: 'v1')
      h2 = described_class.new(index_interpreter, history_cache: cache, interpreter_version: 'v2')

      h1.build_history(tx)
      h2.build_history(tx)

      expect(cache.size).to eq(2)
    end

    it 'mutating returned array does not corrupt the cache' do
      tx = make_tx
      historian = described_class.new(index_interpreter, history_cache: cache)
      result1 = historian.build_history(tx)
      result1 << 99

      result2 = historian.build_history(tx)
      expect(result2).not_to include(99)
    end

    it 'uses a context-dependent cache key' do
      tx = make_tx
      context_interpreter = ->(_, idx, ctx) { ctx == 'a' ? idx : nil }
      historian = described_class.new(context_interpreter, history_cache: cache)

      historian.build_history(tx, 'a')
      historian.build_history(tx, 'b')

      expect(cache.size).to eq(2)
    end

    it 'uses ctx_key_fn when provided' do
      tx = make_tx
      ctx_key_fn = ->(ctx) { ctx.nil? ? 'empty' : ctx.to_s.upcase }
      historian = described_class.new(index_interpreter, history_cache: cache, ctx_key_fn: ctx_key_fn)

      historian.build_history(tx, 'hello')
      expect(cache.keys.first).to include('HELLO')
    end
  end
end
