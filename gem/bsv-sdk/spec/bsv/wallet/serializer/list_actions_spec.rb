# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleDescribes

LIST_ACTIONS_TXID1 = '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
LIST_ACTIONS_TXID2 = 'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234'

RSpec.describe 'BSV::Wallet::Serializer::ListActionsArgs' do
  let(:mod) { BSV::Wallet::Serializer::ListActionsArgs }

  describe 'minimal args round-trip' do
    it 'round-trips empty args' do
      bytes  = mod.serialize({})
      result = mod.deserialize(bytes)
      expect(result[:label_query_mode]).to be_nil
      expect(result[:include_labels]).to be_nil
    end
  end

  describe 'label_query_mode encoding' do
    it 'encodes :any as 0x01' do
      bytes = mod.serialize(label_query_mode: :any)
      result = mod.deserialize(bytes)
      expect(result[:label_query_mode]).to eq(:any)
    end

    it 'encodes :all as 0x02' do
      bytes = mod.serialize(label_query_mode: :all)
      result = mod.deserialize(bytes)
      expect(result[:label_query_mode]).to eq(:all)
    end

    it 'absent mode round-trips as nil' do
      bytes = mod.serialize({})
      result = mod.deserialize(bytes)
      expect(result[:label_query_mode]).to be_nil
    end
  end

  describe 'include flags' do
    it 'round-trips all include flags toggled true' do
      args = {
        include_labels: true,
        include_inputs: true,
        include_input_source_locking_scripts: true,
        include_input_unlocking_scripts: true,
        include_outputs: true,
        include_output_locking_scripts: true
      }
      result = mod.deserialize(mod.serialize(args))
      expect(result[:include_labels]).to be(true)
      expect(result[:include_inputs]).to be(true)
      expect(result[:include_input_source_locking_scripts]).to be(true)
      expect(result[:include_input_unlocking_scripts]).to be(true)
      expect(result[:include_outputs]).to be(true)
      expect(result[:include_output_locking_scripts]).to be(true)
    end

    it 'round-trips all include flags false' do
      args = {
        include_labels: false,
        include_inputs: false,
        include_outputs: false
      }
      result = mod.deserialize(mod.serialize(args))
      expect(result[:include_labels]).to be(false)
      expect(result[:include_inputs]).to be(false)
      expect(result[:include_outputs]).to be(false)
    end

    it 'absent flags round-trip as nil' do
      result = mod.deserialize(mod.serialize({}))
      expect(result[:include_labels]).to be_nil
      expect(result[:include_inputs]).to be_nil
    end
  end

  describe 'limit and offset' do
    it 'round-trips limit and offset' do
      args   = { limit: 50, offset: 10 }
      result = mod.deserialize(mod.serialize(args))
      expect(result[:limit]).to eq(50)
      expect(result[:offset]).to eq(10)
    end

    it 'absent limit/offset round-trips as nil' do
      result = mod.deserialize(mod.serialize({}))
      expect(result[:limit]).to be_nil
      expect(result[:offset]).to be_nil
    end
  end

  describe 'labels' do
    it 'round-trips labels array' do
      args   = { labels: %w[label1 label2] }
      result = mod.deserialize(mod.serialize(args))
      expect(result[:labels]).to eq(%w[label1 label2])
    end

    it 'nil labels round-trips as nil' do
      result = mod.deserialize(mod.serialize(labels: nil))
      expect(result[:labels]).to be_nil
    end
  end

  describe 'full args round-trip' do
    let(:args) do
      {
        labels: ['label1'],
        label_query_mode: :any,
        include_labels: true,
        include_inputs: false,
        include_input_source_locking_scripts: true,
        include_input_unlocking_scripts: false,
        include_outputs: true,
        include_output_locking_scripts: false,
        limit: 100,
        offset: 0,
        seek_permission: true
      }
    end

    it 'round-trips all fields' do
      bytes  = mod.serialize(args)
      result = mod.deserialize(bytes)
      expect(result[:labels]).to eq(['label1'])
      expect(result[:label_query_mode]).to eq(:any)
      expect(result[:include_labels]).to be(true)
      expect(result[:include_inputs]).to be(false)
      expect(result[:limit]).to eq(100)
      expect(result[:offset]).to eq(0)
      expect(result[:seek_permission]).to be(true)
    end
  end
end

RSpec.describe 'BSV::Wallet::Serializer::ListActionsResult' do
  let(:mod) { BSV::Wallet::Serializer::ListActionsResult }

  describe 'empty result' do
    it 'round-trips total_actions: 0, empty actions' do
      result_hash = { total_actions: 0, actions: [] }
      bytes  = mod.serialize(result_hash)
      result = mod.deserialize(bytes)
      expect(result[:total_actions]).to eq(0)
      expect(result[:actions]).to eq([])
    end
  end

  describe 'action statuses' do
    %i[completed unprocessed sending unproven unsigned no_send non_final].each do |status|
      it "round-trips status: #{status}" do
        action = {
          txid: LIST_ACTIONS_TXID1,
          satoshis: 100,
          status: status,
          is_outgoing: true,
          description: 'test',
          version: 1,
          lock_time: 0
        }
        result_hash = { total_actions: 1, actions: [action] }
        bytes  = mod.serialize(result_hash)
        result = mod.deserialize(bytes)
        expect(result[:actions][0][:status]).to eq(status)
      end
    end
  end

  describe 'full action with inputs and outputs' do
    let(:action) do
      {
        txid: LIST_ACTIONS_TXID1,
        satoshis: 1000,
        status: :completed,
        is_outgoing: true,
        description: 'test action',
        labels: ['label1'],
        version: 1,
        lock_time: 0,
        inputs: [
          {
            source_outpoint: "#{LIST_ACTIONS_TXID2}.0",
            source_satoshis: 2000,
            source_locking_script: "\x76\xa9\x14".b,
            unlocking_script: "\xab\xcd".b,
            input_description: 'input 1',
            sequence_number: 0xFFFFFFFF
          }
        ],
        outputs: [
          {
            output_index: 0,
            satoshis: 999,
            locking_script: "\x76\xa9\x14".b,
            spendable: true,
            output_description: 'output 1',
            basket: 'default',
            tags: ['tag1'],
            custom_instructions: 'custom'
          }
        ]
      }
    end

    it 'round-trips full action' do
      result_hash = { total_actions: 1, actions: [action] }
      bytes  = mod.serialize(result_hash)
      result = mod.deserialize(bytes)
      a = result[:actions][0]
      expect(a[:txid]).to eq(LIST_ACTIONS_TXID1)
      expect(a[:satoshis]).to eq(1000)
      expect(a[:status]).to eq(:completed)
      expect(a[:is_outgoing]).to be(true)
      expect(a[:description]).to eq('test action')
      expect(a[:labels]).to eq(['label1'])
      expect(a[:inputs][0][:source_outpoint]).to eq("#{LIST_ACTIONS_TXID2}.0")
      expect(a[:inputs][0][:source_satoshis]).to eq(2000)
      expect(a[:inputs][0][:sequence_number]).to eq(0xFFFFFFFF)
      expect(a[:outputs][0][:satoshis]).to eq(999)
      expect(a[:outputs][0][:spendable]).to be(true)
      expect(a[:outputs][0][:custom_instructions]).to eq('custom')
    end
  end

  describe 'nil inputs and outputs' do
    it 'nil inputs round-trips as nil' do
      action = {
        txid: LIST_ACTIONS_TXID1,
        satoshis: 0,
        status: :completed,
        is_outgoing: false,
        description: '',
        version: 0,
        lock_time: 0,
        inputs: nil,
        outputs: nil
      }
      result_hash = { total_actions: 1, actions: [action] }
      bytes  = mod.serialize(result_hash)
      result = mod.deserialize(bytes)
      expect(result[:actions][0][:inputs]).to be_nil
      expect(result[:actions][0][:outputs]).to be_nil
    end
  end

  describe 'zero satoshis' do
    it 'round-trips 0 satoshis' do
      action = {
        txid: LIST_ACTIONS_TXID1,
        satoshis: 0,
        status: :completed,
        is_outgoing: false,
        description: '',
        version: 0,
        lock_time: 0
      }
      bytes  = mod.serialize(total_actions: 1, actions: [action])
      result = mod.deserialize(bytes)
      expect(result[:actions][0][:satoshis]).to eq(0)
    end
  end

  describe 'invalid status code' do
    it 'raises on unknown status byte' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_varint(1) # 1 action
      w.write_bytes([LIST_ACTIONS_TXID1].pack('H*').reverse)
      w.write_varint(100)
      w.write_byte(99) # invalid status
      expect { mod.deserialize(w.buf) }.to raise_error(ArgumentError, /status/)
    end
  end
end

# rubocop:enable RSpec/MultipleDescribes
