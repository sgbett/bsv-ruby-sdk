# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Overlay error classes' do
  describe BSV::Overlay::OverlayError do
    it 'inherits from StandardError' do
      expect(described_class.ancestors).to include(StandardError)
    end

    it 'can be raised and rescued as StandardError' do
      expect { raise described_class, 'test' }.to raise_error(StandardError)
    end
  end

  describe BSV::Overlay::NoCompetentHostsError do
    it 'inherits from OverlayError' do
      expect(described_class.ancestors).to include(BSV::Overlay::OverlayError)
    end

    it 'can be raised and rescued as OverlayError' do
      expect { raise described_class, 'no hosts' }.to raise_error(BSV::Overlay::OverlayError)
    end

    it 'carries a message' do
      error = described_class.new('no competent hosts found')
      expect(error.message).to eq('no competent hosts found')
    end
  end

  describe BSV::Overlay::AllHostsRejectedError do
    it 'inherits from OverlayError' do
      expect(described_class.ancestors).to include(BSV::Overlay::OverlayError)
    end

    it 'can be raised and rescued as OverlayError' do
      expect { raise described_class, 'all rejected' }.to raise_error(BSV::Overlay::OverlayError)
    end
  end

  describe BSV::Overlay::AcknowledgementError do
    it 'inherits from OverlayError' do
      expect(described_class.ancestors).to include(BSV::Overlay::OverlayError)
    end

    it 'can be raised and rescued as OverlayError' do
      expect { raise described_class, 'ack failed' }.to raise_error(BSV::Overlay::OverlayError)
    end
  end

  it 'loads BSV::Overlay without error' do
    expect { BSV::Overlay }.not_to raise_error
  end
end
# rubocop:enable RSpec/DescribeClass
