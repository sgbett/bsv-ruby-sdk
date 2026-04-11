# frozen_string_literal: true

RSpec.describe BSV::Transaction::Sighash do
  it 'defines ALL as 0x01' do
    expect(described_class::ALL).to eq(0x01)
  end

  it 'defines NONE as 0x02' do
    expect(described_class::NONE).to eq(0x02)
  end

  it 'defines SINGLE as 0x03' do
    expect(described_class::SINGLE).to eq(0x03)
  end

  it 'defines ANYONE_CAN_PAY as 0x80' do
    expect(described_class::ANYONE_CAN_PAY).to eq(0x80)
  end

  it 'defines FORK_ID as 0x40' do
    expect(described_class::FORK_ID).to eq(0x40)
  end

  it 'defines ALL_FORK_ID as 0x41' do
    expect(described_class::ALL_FORK_ID).to eq(0x41)
  end
end
