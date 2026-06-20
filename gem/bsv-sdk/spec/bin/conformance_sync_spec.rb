# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

# Load the sync script without executing its main block.
$PROGRAM_NAME_ORIG = $PROGRAM_NAME # rubocop:disable Style/GlobalVars
load File.expand_path('../../../../bin/conformance/sync', __dir__)

RSpec.describe 'ConformanceSync pure helpers' do
  let(:good_sha) { 'c094b60029a6340a12e7da7449cf72c06b11cd7c' }
  let(:short_sha) { 'abc123' }
  let(:branch_ref) { 'main' }
  let(:tag_ref) { 'v1.0.0' }

  # --- SHA validation ---

  describe '.validate_sha!' do
    it 'accepts a valid 40-char lowercase hex SHA' do
      expect { ConformanceSync.validate_sha!(good_sha) }.not_to raise_error
    end

    it 'rejects a partial SHA' do
      expect { ConformanceSync.validate_sha!(short_sha) }.to raise_error(ConformanceSync::Error, /40-char hex SHA/)
    end

    it 'rejects a branch name' do
      expect { ConformanceSync.validate_sha!(branch_ref) }.to raise_error(ConformanceSync::Error, /40-char hex SHA/)
    end

    it 'rejects a tag' do
      expect { ConformanceSync.validate_sha!(tag_ref) }.to raise_error(ConformanceSync::Error, /40-char hex SHA/)
    end

    it 'rejects a SHA with uppercase characters' do
      upper_sha = good_sha.upcase
      expect { ConformanceSync.validate_sha!(upper_sha) }.to raise_error(ConformanceSync::Error, /40-char hex SHA/)
    end
  end

  # --- Lock file read/write ---

  describe '.lock_write and .lock_read' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:lock_path) { File.join(tmpdir, 'conformance.lock') }
    let(:expected_fields) do
      {
        'upstream' => 'bsv-blockchain/ts-stack',
        'path' => 'conformance/',
        'sha' => good_sha,
        'fetched_at' => Date.today.to_s,
        'tarball_sha256' => 'deadbeef' * 8,
        'vectors_count' => '73',
        'vectors_total' => '6646'
      }
    end

    before { stub_const('ConformanceSync::LOCK_PATH', lock_path) }

    after { FileUtils.rm_rf(tmpdir) }

    it 'round-trips all fields through write/read' do
      ConformanceSync.lock_write(
        sha: good_sha,
        tarball_sha256: 'deadbeef' * 8,
        vectors_count: 73,
        vectors_total: 6646
      )
      lock = ConformanceSync.lock_read
      expect(lock).to eq(expected_fields)
    end

    it 'returns an empty hash when the lock file does not exist' do
      expect(ConformanceSync.lock_read).to eq({})
    end

    it 'writes a comment header that is ignored by the reader' do
      ConformanceSync.lock_write(sha: good_sha, tarball_sha256: 'aa' * 32, vectors_count: 1, vectors_total: 1)
      raw = File.read(ConformanceSync::LOCK_PATH)
      expect(raw).to include('# Auto-managed by bin/conformance/sync')
      expect(ConformanceSync.lock_read).not_to have_key('#')
    end
  end

  # --- Cache validity check ---

  describe '.cache_valid?' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:cache_dir) { File.join(tmpdir, 'conformance-vectors') }

    before { stub_const('ConformanceSync::CACHE_DIR', cache_dir) }

    after { FileUtils.rm_rf(tmpdir) }

    it 'returns false when cache directory does not exist' do
      expect(ConformanceSync.cache_valid?('aa' * 32)).to be false
    end

    it 'returns false when META.json is missing' do
      FileUtils.mkdir_p(File.join(ConformanceSync::CACHE_DIR, 'conformance'))
      expect(ConformanceSync.cache_valid?('aa' * 32)).to be false
    end

    it 'returns false when expected_sha256 is nil' do
      meta_dir = File.join(ConformanceSync::CACHE_DIR, 'conformance')
      FileUtils.mkdir_p(meta_dir)
      File.write(File.join(meta_dir, 'META.json'), '{}')
      expect(ConformanceSync.cache_valid?(nil)).to be false
    end

    it 'returns true when META.json exists and sha256 is provided' do
      meta_dir = File.join(ConformanceSync::CACHE_DIR, 'conformance')
      FileUtils.mkdir_p(meta_dir)
      File.write(File.join(meta_dir, 'META.json'), '{}')
      expect(ConformanceSync.cache_valid?('aa' * 32)).to be true
    end
  end

  # --- Argument parsing ---

  describe '.parse_args' do
    it 'returns [sha, nil] with no --update flag' do
      sha, update = ConformanceSync.parse_args([good_sha])
      expect(sha).to eq(good_sha)
      expect(update).to be_nil
    end

    it 'returns [sha, "--update"] when --update is present' do
      sha, update = ConformanceSync.parse_args([good_sha, '--update'])
      expect(sha).to eq(good_sha)
      expect(update).to eq('--update')
    end

    it 'returns [nil, nil] when called with no arguments' do
      sha, update = ConformanceSync.parse_args([])
      expect(sha).to be_nil
      expect(update).to be_nil
    end
  end

  # --- SHA resolution from lock ---

  describe '.resolve_sha_from_lock' do
    it 'reads SHA from lock when none given' do
      sha, = ConformanceSync.resolve_sha_from_lock(nil, { 'sha' => good_sha }, nil)
      expect(sha).to eq(good_sha)
    end

    it 'raises an informative error when no SHA and no lock' do
      expect do
        ConformanceSync.resolve_sha_from_lock(nil, {}, nil)
      end.to raise_error(ConformanceSync::Error, /No SHA given/)
    end

    it 'uses the provided SHA when given' do
      sha, = ConformanceSync.resolve_sha_from_lock(good_sha, {}, nil)
      expect(sha).to eq(good_sha)
    end
  end
end
