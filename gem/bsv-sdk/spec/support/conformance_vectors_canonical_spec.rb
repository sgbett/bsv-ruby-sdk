# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass

require 'spec_helper'
require 'support/conformance_vectors'

RSpec.describe 'ConformanceVectors canonical loader' do
  describe '.canonical' do
    it 'returns the parsed envelope for a dot-separated ID' do
      envelope = ConformanceVectors.canonical('sdk.keys.public-key')
      expect(envelope['id']).to eq('sdk.keys.publickey')
    end

    it 'resolves hyphens within the final segment correctly (auth.brc31-handshake)' do
      # auth/brc31-handshake.json — dots → slashes, hyphens stay
      path = File.join(ConformanceVectors::CANONICAL_DIR, 'auth/brc31-handshake.json')
      skip 'auth/brc31-handshake.json not present in cache' unless File.exist?(path)

      envelope = ConformanceVectors.canonical('auth.brc31-handshake')
      expect(envelope).to be_a(Hash)
    end

    it 'resolves subdomain IDs with multiple dot segments (messaging.brc31.authrite-signature)' do
      path = File.join(ConformanceVectors::CANONICAL_DIR, 'messaging/brc31/authrite-signature.json')
      skip 'messaging/brc31/authrite-signature.json not present in cache' unless File.exist?(path)

      envelope = ConformanceVectors.canonical('messaging.brc31.authrite-signature')
      expect(envelope).to be_a(Hash)
    end

    it 'raises a clear error for an unknown ID' do
      expect { ConformanceVectors.canonical('sdk.keys.does-not-exist') }
        .to raise_error(/Canonical vector not found/)
    end
  end

  describe '.each_canonical_vector' do
    it 'yields once per non-skipped vector' do
      yielded = []
      ConformanceVectors.each_canonical_vector('sdk.keys.public-key') do |_envelope, vector|
        yielded << vector['id']
      end
      envelope = ConformanceVectors.canonical('sdk.keys.public-key')
      expected_count = envelope['vectors'].count { |v| !v['skip'] }
      expect(yielded.length).to eq(expected_count)
    end

    it 'skips vectors with skip: true and logs the reason' do
      path = File.join(ConformanceVectors::CANONICAL_DIR, 'sdk/scripts/evaluation.json')
      skip 'sdk/scripts/evaluation.json not present in cache' unless File.exist?(path)

      yielded = []
      warnings = []
      allow_any_instance_of(Object).to receive(:warn) { |_, msg| warnings << msg } # rubocop:disable RSpec/AnyInstance
      ConformanceVectors.each_canonical_vector('sdk.scripts.evaluation') do |_env, vec|
        yielded << vec['id']
      end

      envelope = ConformanceVectors.canonical('sdk.scripts.evaluation')
      skip_count = envelope['vectors'].count { |v| v['skip'] }
      expect(warnings.length).to eq(skip_count)
      expect(warnings.first).to match(/skipping.*:/)
    end
  end

  describe '.canonical_regression' do
    it 'returns the parsed regression envelope' do
      envelope = ConformanceVectors.canonical_regression('beef-isvalid-hydration')
      expect(envelope).to be_a(Hash)
      expect(envelope['vectors']).to be_an(Array)
      expect(envelope['vectors']).not_to be_empty
    end

    it 'raises for a missing regression' do
      expect { ConformanceVectors.canonical_regression('no-such-regression') }
        .to raise_error(/Canonical regression not found/)
    end
  end

  describe 'missing cache guard' do
    it 'raises an actionable error when the cache directory is missing' do
      stub_const('ConformanceVectors::CANONICAL_DIR', '/tmp/bsv-conformance-cache-does-not-exist')
      expect { ConformanceVectors.canonical('sdk.keys.public-key') }
        .to raise_error(%r{Run bin/conformance/sync first})
    end
  end
end

# rubocop:enable RSpec/DescribeClass
