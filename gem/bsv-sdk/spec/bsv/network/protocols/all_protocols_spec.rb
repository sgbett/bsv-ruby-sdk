# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass
require 'spec_helper'

RSpec.describe 'BSV::Network::Protocols integration' do
  # Verify all 5 protocol classes load correctly via autoload.
  describe 'autoloads' do
    it 'loads ARC' do
      expect(BSV::Network::Protocols::ARC).to be < BSV::Network::Protocol
    end

    it 'loads WoCREST' do
      expect(BSV::Network::Protocols::WoCREST).to be < BSV::Network::Protocol
    end

    it 'loads Chaintracks' do
      expect(BSV::Network::Protocols::Chaintracks).to be < BSV::Network::Protocol
    end

    it 'loads Ordinals' do
      expect(BSV::Network::Protocols::Ordinals).to be < BSV::Network::Protocol
    end

    it 'loads TAALBinary' do
      expect(BSV::Network::Protocols::TAALBinary).to be < BSV::Network::Protocol
    end
  end

  # Verify command counts and no intra-protocol collisions.
  describe 'command sets' do
    describe 'ARC' do
      subject(:commands) { BSV::Network::Protocols::ARC.commands }

      it 'has 5 commands' do
        expect(commands.size).to eq(5)
      end

      it 'includes the expected commands' do
        expect(commands).to include(:broadcast, :broadcast_many, :get_tx_status, :get_policy, :health)
      end

      it 'has no duplicate command names' do
        expect(commands.size).to eq(commands.to_a.uniq.size)
      end
    end

    describe 'WoCREST' do
      subject(:commands) { BSV::Network::Protocols::WoCREST.commands }

      it 'has 13 commands' do
        expect(commands.size).to eq(13)
      end

      it 'includes the expected commands' do
        expect(commands).to include(
          :current_height, :get_block_header, :get_tx, :get_merkle_path,
          :broadcast, :get_tx_status, :get_utxos, :is_utxo,
          :valid_root, :get_script_unspent, :get_balance, :health
        )
      end

      it 'has no duplicate command names' do
        expect(commands.size).to eq(commands.to_a.uniq.size)
      end
    end

    describe 'Chaintracks' do
      subject(:commands) { BSV::Network::Protocols::Chaintracks.commands }

      it 'has 2 commands' do
        expect(commands.size).to eq(2)
      end

      it 'includes the expected commands' do
        expect(commands).to include(:get_block_header, :current_height)
      end

      it 'has no duplicate command names' do
        expect(commands.size).to eq(commands.to_a.uniq.size)
      end
    end

    describe 'Ordinals' do
      subject(:commands) { BSV::Network::Protocols::Ordinals.commands }

      it 'has 2 commands' do
        expect(commands.size).to eq(2)
      end

      it 'includes the expected commands' do
        expect(commands).to include(:get_tx, :get_merkle_path)
      end

      it 'has no duplicate command names' do
        expect(commands.size).to eq(commands.to_a.uniq.size)
      end
    end

    describe 'TAALBinary' do
      subject(:commands) { BSV::Network::Protocols::TAALBinary.commands }

      it 'has 1 command' do
        expect(commands.size).to eq(1)
      end

      it 'includes the expected commands' do
        expect(commands).to include(:broadcast)
      end

      it 'has no duplicate command names' do
        expect(commands.size).to eq(commands.to_a.uniq.size)
      end
    end
  end

  # Verify that protocols sharing a command name are distinct classes.
  describe 'shared command names across protocols' do
    it ':broadcast is declared by ARC, WoCREST, and TAALBinary as distinct classes' do
      classes = [
        BSV::Network::Protocols::ARC,
        BSV::Network::Protocols::WoCREST,
        BSV::Network::Protocols::TAALBinary
      ]
      expect(classes.all? { |klass| klass.commands.include?(:broadcast) }).to be(true)
      expect(classes.uniq.size).to eq(3)
    end

    it ':current_height is declared by WoCREST and Chaintracks as distinct classes' do
      classes = [
        BSV::Network::Protocols::WoCREST,
        BSV::Network::Protocols::Chaintracks
      ]
      expect(classes.all? { |klass| klass.commands.include?(:current_height) }).to be(true)
      expect(classes.uniq.size).to eq(2)
    end

    it ':get_block_header is declared by WoCREST and Chaintracks as distinct classes' do
      classes = [
        BSV::Network::Protocols::WoCREST,
        BSV::Network::Protocols::Chaintracks
      ]
      expect(classes.all? { |klass| klass.commands.include?(:get_block_header) }).to be(true)
      expect(classes.uniq.size).to eq(2)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
