# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass
require 'spec_helper'

RSpec.describe 'BSV::Network::Protocols integration' do
  # Verify all 7 protocol classes load correctly via autoload.
  describe 'autoloads' do
    it 'loads ARC' do
      expect(BSV::Network::Protocols::ARC).to be < BSV::Network::Protocol
    end

    it 'loads Arcade' do
      expect(BSV::Network::Protocols::Arcade).to be < BSV::Network::Protocol
    end

    it 'loads Chaintracks' do
      expect(BSV::Network::Protocols::Chaintracks).to be < BSV::Network::Protocol
    end

    it 'loads JungleBus' do
      expect(BSV::Network::Protocols::JungleBus).to be < BSV::Network::Protocol
    end

    it 'loads Ordinals' do
      expect(BSV::Network::Protocols::Ordinals).to be < BSV::Network::Protocol
    end

    it 'loads TAALBinary' do
      expect(BSV::Network::Protocols::TAALBinary).to be < BSV::Network::Protocol
    end

    it 'loads WoCREST' do
      expect(BSV::Network::Protocols::WoCREST).to be < BSV::Network::Protocol
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

    describe 'Arcade' do
      subject(:commands) { BSV::Network::Protocols::Arcade.commands }

      it 'has 3 commands' do
        expect(commands.size).to eq(3)
      end

      it 'includes exactly the expected commands' do
        expect(commands).to eq(Set.new(%i[broadcast get_tx_status health]))
      end

      it 'has no duplicate command names' do
        expect(commands.size).to eq(commands.to_a.uniq.size)
      end
    end

    describe 'WoCREST' do
      subject(:commands) { BSV::Network::Protocols::WoCREST.commands }

      it 'has 54 commands' do
        expect(commands.size).to eq(54)
      end

      it 'includes the expected commands' do
        expect(commands).to include(
          # Chain
          :current_height, :get_chain_info, :get_block_header, :get_block_headers,
          :get_circulating_supply, :get_chain_tips, :get_peer_info,
          # Transaction
          :get_tx, :get_tx_details, :get_output_script, :get_opreturn,
          :get_merkle_path, :broadcast, :decode_tx, :get_tx_status,
          :get_tx_hex_bulk, :get_tx_binary, :get_tx_by_block_index,
          :get_tx_propagation, :get_bulk_tx_details, :get_bulk_output_scripts,
          # UTXO / spent status
          :get_utxos, :get_utxos_all, :is_utxo, :is_utxo_bulk, :valid_root,
          :get_unconfirmed_utxos, :get_confirmed_spent, :get_unconfirmed_spent,
          :get_bulk_address_utxos, :get_bulk_address_unconfirmed_utxos,
          # Script
          :get_script_unspent, :get_script_history, :get_script_all_unspent,
          :get_script_unspent_bulk, :get_script_unconfirmed_unspent,
          :get_bulk_script_unconfirmed_unspent,
          # Address
          :get_balance, :get_unconfirmed_balance, :get_history, :is_address_used,
          # Exchange rate / fees / mempool
          :get_exchange_rate, :get_fee_recommendation, :get_mempool_info,
          :get_exchange_rate_historical, :get_mempool_raw,
          # Search
          :search_links,
          # Stats
          :get_block_stats, :get_block_stats_by_hash, :get_miner_block_stats,
          :get_miner_fees, :get_miner_summary, :get_block_tag_count,
          # Health
          :health
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

    describe 'JungleBus' do
      subject(:commands) { BSV::Network::Protocols::JungleBus.commands }

      it 'has 6 commands' do
        expect(commands.size).to eq(6)
      end

      it 'includes the expected commands' do
        expect(commands).to include(
          :get_tx, :get_address_meta, :get_address_txs,
          :get_block_header, :get_block_headers, :current_height
        )
      end

      it 'has no duplicate command names' do
        expect(commands.size).to eq(commands.to_a.uniq.size)
      end
    end

    describe 'Ordinals' do
      subject(:commands) { BSV::Network::Protocols::Ordinals.commands }

      it 'has 8 commands' do
        expect(commands.size).to eq(8)
      end

      it 'includes the expected commands' do
        expect(commands).to include(
          :get_tx, :get_tx_details, :get_tx_status,
          :get_merkle_path, :get_utxos, :get_balance,
          :get_spend, :get_chain_tip
        )
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
    it ':broadcast is declared by ARC, Arcade, WoCREST, and TAALBinary as distinct classes' do
      classes = [
        BSV::Network::Protocols::ARC,
        BSV::Network::Protocols::Arcade,
        BSV::Network::Protocols::WoCREST,
        BSV::Network::Protocols::TAALBinary
      ]
      expect(classes.all? { |klass| klass.commands.include?(:broadcast) }).to be(true)
      expect(classes.uniq.size).to eq(4)
    end

    it ':current_height is declared by WoCREST, Chaintracks, and JungleBus as distinct classes' do
      classes = [
        BSV::Network::Protocols::WoCREST,
        BSV::Network::Protocols::Chaintracks,
        BSV::Network::Protocols::JungleBus
      ]
      expect(classes.all? { |klass| klass.commands.include?(:current_height) }).to be(true)
      expect(classes.uniq.size).to eq(3)
    end

    it ':get_block_header is declared by WoCREST, Chaintracks, and JungleBus as distinct classes' do
      classes = [
        BSV::Network::Protocols::WoCREST,
        BSV::Network::Protocols::Chaintracks,
        BSV::Network::Protocols::JungleBus
      ]
      expect(classes.all? { |klass| klass.commands.include?(:get_block_header) }).to be(true)
      expect(classes.uniq.size).to eq(3)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
