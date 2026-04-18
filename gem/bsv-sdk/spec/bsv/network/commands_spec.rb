# frozen_string_literal: true

# Eagerly load Commands so the registry is populated before each example.
require 'bsv/network/commands'

ALL_COMMAND_NAMES = %i[
  broadcast
  broadcast_many
  get_tx
  get_tx_status
  get_utxos
  is_utxo
  get_merkle_path
  valid_root
  current_height
  get_script_unspent
  get_policy
].freeze

RSpec.describe 'BSV::Network::Commands' do
  # Use a real but isolated registry by NOT calling reset! — Commands are
  # registered at load time (module-eval), so they are already present.
  # We must NOT reset! between examples or the define calls won't rerun.

  describe 'command registration' do
    it 'registers exactly 11 commands' do
      count = ALL_COMMAND_NAMES.count { |name| BSV::Network::Command.find(name) }
      expect(count).to eq(11)
    end

    ALL_COMMAND_NAMES.each do |name|
      it "registers :#{name}" do
        expect(BSV::Network::Command.find(name)).to be_a(BSV::Network::Command)
      end
    end
  end

  describe 'command metadata' do
    subject(:cmd) { BSV::Network::Command.find(command_name) }

    context ':broadcast' do
      let(:command_name) { :broadcast }

      it { is_expected.not_to be_nil }
      it('has a description') { expect(cmd.description).not_to be_empty }
      it('includes tx param') { expect(cmd.params).to have_key(:tx) }
      it('returns shape includes txid') { expect(cmd.returns).to include('txid') }
    end

    context ':broadcast_many' do
      let(:command_name) { :broadcast_many }

      it { is_expected.not_to be_nil }
      it('has a description') { expect(cmd.description).not_to be_empty }
      it('includes txs param') { expect(cmd.params).to have_key(:txs) }
    end

    context ':get_tx' do
      let(:command_name) { :get_tx }

      it { is_expected.not_to be_nil }
      it('includes txid param') { expect(cmd.params).to have_key(:txid) }
      it('returns raw hex') { expect(cmd.returns).to include('hex') }
    end

    context ':get_tx_status' do
      let(:command_name) { :get_tx_status }

      it { is_expected.not_to be_nil }
      it('includes txid param') { expect(cmd.params).to have_key(:txid) }
      it('returns includes tx_status') { expect(cmd.returns).to include('tx_status') }
    end

    context ':get_utxos' do
      let(:command_name) { :get_utxos }

      it { is_expected.not_to be_nil }
      it('includes address param') { expect(cmd.params).to have_key(:address) }
      it('returns an array') { expect(cmd.returns).to include('Array') }
    end

    context ':is_utxo' do
      let(:command_name) { :is_utxo }

      it { is_expected.not_to be_nil }
      it('includes txid param') { expect(cmd.params).to have_key(:txid) }
      it('includes vout param') { expect(cmd.params).to have_key(:vout) }
      it('includes optional script_hash param') { expect(cmd.params).to have_key(:script_hash) }
      it('marks script_hash as optional') { expect(cmd.params[:script_hash]).to include('optional') }
      it('returns Boolean') { expect(cmd.returns).to eq('Boolean') }
    end

    context ':get_merkle_path' do
      let(:command_name) { :get_merkle_path }

      it { is_expected.not_to be_nil }
      it('includes txid param') { expect(cmd.params).to have_key(:txid) }
      it('returns TSC proof components') { expect(cmd.returns).to include('TSC') }
      it('mentions index in return description') { expect(cmd.returns).to include('index') }
    end

    context ':valid_root' do
      let(:command_name) { :valid_root }

      it { is_expected.not_to be_nil }
      it('includes root param') { expect(cmd.params).to have_key(:root) }
      it('includes height param') { expect(cmd.params).to have_key(:height) }
      it('returns Boolean') { expect(cmd.returns).to eq('Boolean') }
    end

    context ':current_height' do
      let(:command_name) { :current_height }

      it { is_expected.not_to be_nil }
      it('accepts no params') { expect(cmd.params).to be_empty }
      it('returns Integer') { expect(cmd.returns).to eq('Integer') }
    end

    context ':get_script_unspent' do
      let(:command_name) { :get_script_unspent }

      it { is_expected.not_to be_nil }
      it('includes script_hash param') { expect(cmd.params).to have_key(:script_hash) }
      it('returns an array') { expect(cmd.returns).to include('Array') }
    end

    context ':get_policy' do
      let(:command_name) { :get_policy }

      it { is_expected.not_to be_nil }
      it('accepts no params') { expect(cmd.params).to be_empty }
      it('returns policy hash') { expect(cmd.returns).to include('policy') }
    end
  end

  describe 'idempotent loading' do
    it 'does not raise when the file is required a second time' do
      expect { require 'bsv/network/commands' }.not_to raise_error
    end
  end
end
