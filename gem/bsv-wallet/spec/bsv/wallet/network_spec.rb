# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::Client do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:storage) { BSV::Wallet::Store::Memory.new }
  let(:chain_data_source) { double('chain_data_source') } # rubocop:disable RSpec/VerifiedDoubles

  describe '#get_height' do
    context 'when neither substrate nor chain_data_source is configured' do
      subject(:client) { described_class.new(private_key, storage: storage, allow_memory_store: true) }

      it 'raises UnsupportedActionError' do
        expect { client.get_height }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end

      it 'includes a helpful message' do
        expect { client.get_height }
          .to raise_error(BSV::Wallet::UnsupportedActionError, /chain data source or remote substrate/)
      end
    end

    context 'when chain_data_source is configured (no substrate)' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end

      it 'returns the height from the chain data source' do
        allow(chain_data_source).to receive(:current_height).and_return(850_000)

        expect(client.get_height).to eq({ height: 850_000 })
      end

      it 'wraps the result in a hash with a :height key' do
        allow(chain_data_source).to receive(:current_height).and_return(1)

        result = client.get_height
        expect(result).to be_a(Hash)
        expect(result).to have_key(:height)
      end

      it 'passes through height 0 (genesis) unchanged' do
        allow(chain_data_source).to receive(:current_height).and_return(0)

        expect(client.get_height).to eq({ height: 0 })
      end

      it 'propagates errors from the chain data source' do
        allow(chain_data_source).to receive(:current_height).and_raise(StandardError, 'network error')

        expect { client.get_height }.to raise_error(StandardError, 'network error')
      end
    end

    context 'when both substrate and chain_data_source are configured' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          substrate: substrate,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end
      let(:substrate) { double('substrate') } # rubocop:disable RSpec/VerifiedDoubles

      it 'delegates to the substrate, not the chain data source' do
        allow(substrate).to receive(:get_height).and_return({ height: 999_999 })
        allow(chain_data_source).to receive(:current_height)

        expect(client.get_height).to eq({ height: 999_999 })
        expect(chain_data_source).not_to have_received(:current_height)
      end

      it 'forwards args and originator to the substrate' do
        allow(substrate).to receive(:get_height).with({}, originator: 'test').and_return({ height: 1 })

        client.get_height({}, originator: 'test')

        expect(substrate).to have_received(:get_height).with({}, originator: 'test')
      end
    end
  end

  describe '#get_header_for_height' do
    let(:sample_header) do
      {
        'hash' => '000000000000000002a4dc25b9ea1a2c327a6a2e7e1c98f0f00b12b8be85f9b',
        'merkleroot' => 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'previousblockhash' => '000000000000000001234567890abcdef1234567890abcdef1234567890abcd',
        'time' => 1_700_000_000,
        'nonce' => 12_345_678,
        'bits' => '1a123456',
        'version' => 536_870_912,
        'height' => 800_000
      }
    end

    context 'when neither substrate nor chain_data_source is configured' do
      subject(:client) { described_class.new(private_key, storage: storage, allow_memory_store: true) }

      it 'raises UnsupportedActionError' do
        expect { client.get_header_for_height({ height: 800_000 }) }
          .to raise_error(BSV::Wallet::UnsupportedActionError)
      end

      it 'includes a helpful message' do
        expect { client.get_header_for_height({ height: 800_000 }) }
          .to raise_error(BSV::Wallet::UnsupportedActionError, /chain_data_source or remote substrate/)
      end
    end

    context 'when chain_data_source is configured (no substrate)' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end

      it 'returns the header from the chain data source' do
        allow(chain_data_source).to receive(:get_block_header).with(800_000).and_return(sample_header)

        expect(client.get_header_for_height({ height: 800_000 })).to eq({ header: sample_header })
      end

      it 'wraps the result in a hash with a :header key' do
        allow(chain_data_source).to receive(:get_block_header).with(800_000).and_return(sample_header)

        result = client.get_header_for_height({ height: 800_000 })
        expect(result).to be_a(Hash)
        expect(result).to have_key(:header)
      end

      it 'allows height 0 (genesis block)' do
        genesis_header = sample_header.merge('height' => 0)
        allow(chain_data_source).to receive(:get_block_header).with(0).and_return(genesis_header)

        expect(client.get_header_for_height({ height: 0 })).to eq({ header: genesis_header })
      end

      it 'raises InvalidParameterError for negative height' do
        expect { client.get_header_for_height({ height: -1 }) }
          .to raise_error(BSV::Wallet::InvalidParameterError)
      end

      it 'raises InvalidParameterError for a non-integer height' do
        expect { client.get_header_for_height({ height: '800000' }) }
          .to raise_error(BSV::Wallet::InvalidParameterError)
      end

      it 'raises InvalidParameterError for nil height' do
        expect { client.get_header_for_height({ height: nil }) }
          .to raise_error(BSV::Wallet::InvalidParameterError)
      end

      it 'raises InvalidParameterError for a float height' do
        expect { client.get_header_for_height({ height: 800_000.0 }) }
          .to raise_error(BSV::Wallet::InvalidParameterError)
      end

      it 'propagates errors from the chain data source' do
        allow(chain_data_source).to receive(:get_block_header).and_raise(StandardError, 'network error')

        expect { client.get_header_for_height({ height: 800_000 }) }
          .to raise_error(StandardError, 'network error')
      end
    end

    context 'when both substrate and chain_data_source are configured' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          substrate: substrate,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end
      let(:substrate) { double('substrate') } # rubocop:disable RSpec/VerifiedDoubles

      it 'delegates to the substrate, not the chain data source' do
        allow(substrate).to receive(:get_header_for_height).and_return({ header: sample_header })
        allow(chain_data_source).to receive(:get_block_header)

        expect(client.get_header_for_height({ height: 800_000 })).to eq({ header: sample_header })
        expect(chain_data_source).not_to have_received(:get_block_header)
      end

      it 'forwards args and originator to the substrate' do
        allow(substrate).to receive(:get_header_for_height)
          .with({ height: 800_000 }, originator: 'test')
          .and_return({ header: sample_header })

        client.get_header_for_height({ height: 800_000 }, originator: 'test')

        expect(substrate).to have_received(:get_header_for_height)
          .with({ height: 800_000 }, originator: 'test')
      end
    end
  end
end
