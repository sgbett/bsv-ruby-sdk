# frozen_string_literal: true

RSpec.describe BSV::Primitives::Polynomial do
  # Static test vectors verified against the Go SDK test suite.
  # These values are taken directly from polynomial_test.go in the go-sdk.
  let(:vector_points) do
    [
      BSV::Primitives::PointInFiniteField.new(
        OpenSSL::BN.new('0'),
        OpenSSL::BN.new('63465989459149561019572730115992841667230613457321334813170901334782306753071')
      ),
      BSV::Primitives::PointInFiniteField.new(
        OpenSSL::BN.new('60098049464719082536908106929717058139237866646407792639097261741118523954739'),
        OpenSSL::BN.new('5445227977440784036220256291344012565233687922480676424981735065099509271083')
      ),
      BSV::Primitives::PointInFiniteField.new(
        OpenSSL::BN.new('1052059428069456700843310926531798840191498924785835970686579452590270423430'),
        OpenSSL::BN.new('98174180884762975979793822263175877424237569238167613939083869503184221497454')
      )
    ]
  end

  let(:vector_expected_shares) do
    [
      { x: OpenSSL::BN.new('1'), y: OpenSSL::BN.new('98209580936265727237729889604490309223950058914015254484773717993541175692579') },
      { x: OpenSSL::BN.new('2'), y: OpenSSL::BN.new('28381905659213213900229646735188926996459360747522498927113843756675333610380') },
      { x: OpenSSL::BN.new('3'), y: OpenSSL::BN.new('85567142102624411854213971525464510691298488289124196219106446640002449849800') },
      { x: OpenSSL::BN.new('4'), y: OpenSSL::BN.new('38181111791866930252540893957941244601927472207539218281836358627704855067513') },
      { x: OpenSSL::BN.new('5'), y: OpenSSL::BN.new('2015903964256964518781399041307036581616297168408129154761163727691383935182') }
    ]
  end

  describe '#initialize' do
    it 'stores points and threshold' do
      points = [BSV::Primitives::PointInFiniteField.new(OpenSSL::BN.new('0'), OpenSSL::BN.new('1'))]
      poly   = described_class.new(points, 1)
      expect(poly.points).to eq(points)
      expect(poly.threshold).to eq(1)
    end

    it 'defaults threshold to points.length when omitted' do
      points = Array.new(3) { BSV::Primitives::PointInFiniteField.new(OpenSSL::BN.new('0'), OpenSSL::BN.new('0')) }
      poly   = described_class.new(points)
      expect(poly.threshold).to eq(3)
    end
  end

  describe '.from_private_key' do
    let(:key) { BSV::Primitives::PrivateKey.generate }

    it 'returns a Polynomial with threshold-many points' do
      poly = described_class.from_private_key(key, threshold: 2)
      expect(poly.points.length).to eq(2)
      expect(poly.threshold).to eq(2)
    end

    it 'places the key scalar at x=0 (first point)' do
      poly = described_class.from_private_key(key, threshold: 3)
      expect(poly.points.first.x).to eq(OpenSSL::BN.new('0'))
      expect(poly.points.first.y).to eq(key.bn)
    end

    it 'returns the secret correctly when evaluated at x=0' do
      poly = described_class.from_private_key(key, threshold: 3)
      recovered = poly.value_at(OpenSSL::BN.new('0'))
      expect(recovered).to eq(key.bn)
    end

    it 'generates different random coefficients on each call' do
      poly1 = described_class.from_private_key(key, threshold: 3)
      poly2 = described_class.from_private_key(key, threshold: 3)
      # The random points (index 1+) should almost certainly differ
      expect(poly1.points[1].x).not_to eq(poly2.points[1].x)
    end
  end

  describe '#value_at' do
    it 'evaluates a constant polynomial (threshold=1) to its single y-value' do
      point = BSV::Primitives::PointInFiniteField.new(OpenSSL::BN.new('0'), OpenSSL::BN.new('42'))
      poly  = described_class.new([point], 1)
      expect(poly.value_at(OpenSSL::BN.new('0'))).to eq(OpenSSL::BN.new('42'))
      expect(poly.value_at(OpenSSL::BN.new('99'))).to eq(OpenSSL::BN.new('42'))
    end

    it 'returns a value in [0, P) for all inputs' do
      p    = BSV::Primitives::PointInFiniteField::P
      poly = described_class.new(vector_points, 3)
      [0, 1, 2, 3, 1_000_000].each do |i|
        result = poly.value_at(OpenSSL::BN.new(i.to_s))
        expect(result).to be >= OpenSSL::BN.new('0')
        expect(result).to be < p
      end
    end

    it 'matches static Go-SDK vectors for shares 1-5' do
      poly = described_class.new(vector_points, 3)
      vector_expected_shares.each do |vec|
        actual = poly.value_at(vec[:x])
        expect(actual).to eq(vec[:y])
      end
    end

    it 'recovers the secret by interpolating at x=0 from any threshold subset' do
      poly   = described_class.new(vector_points, 3)
      secret = poly.value_at(OpenSSL::BN.new('0'))

      # Generate 5 shares and verify that any 3 can reconstruct the secret
      shares = (1..5).map do |i|
        x = OpenSSL::BN.new(i.to_s)
        y = poly.value_at(x)
        BSV::Primitives::PointInFiniteField.new(x, y)
      end

      [[0, 1, 2], [0, 2, 4], [1, 3, 4]].each do |indices|
        subset    = indices.map { |i| shares[i] }
        rec_poly  = described_class.new(subset, 3)
        recovered = rec_poly.value_at(OpenSSL::BN.new('0'))
        expect(recovered).to eq(secret)
      end
    end
  end
end
