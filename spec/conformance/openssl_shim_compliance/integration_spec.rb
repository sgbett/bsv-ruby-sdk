# frozen_string_literal: true

require 'English'
require 'spec_helper'
require 'digest'
require 'fileutils'
require 'tmpdir'

# Context-scoped setup and instance variables are deliberate here: the harness
# is invoked twice as out-of-process Ruby subprocesses (once for stock OpenSSL,
# once for the shim) and the resulting binary fixtures are byte-compared per
# example. Running the harness per example would be ~25x slower with no
# semantic benefit. The shared state (@openssl_dir / @shim_dir) is read-only
# after setup and explicitly cleaned up in after(:context).
# rubocop:disable RSpec/InstanceVariable, RSpec/BeforeAfterAll
RSpec.describe 'OpenSSL EC Shim Integration (process-isolated)' do
  before(:context) do
    # OpenSSL::PKey::EC::Point#add was added in the openssl gem v3.0
    # (bundled with Ruby 3.1+). The harness invokes a fresh subprocess
    # using *stock* OpenSSL (not the shim), so we have to check the Ruby
    # version directly — querying Point.method_defined?(:add) here would
    # see the *shim's* implementation of #add, not stock OpenSSL's.
    # The shim itself has direct unit-test coverage in
    # spec/bsv/primitives/secp256k1_spec.rb that runs on every supported
    # Ruby version.
    skip 'requires openssl gem >= 3.0 (Ruby 3.1+)' if RUBY_VERSION < '3.1'

    @harness      = File.expand_path('integration_harness.rb', __dir__)
    @project_root = File.expand_path('../../..', __dir__)
    @openssl_dir  = Dir.mktmpdir('openssl_compliance_')
    @shim_dir     = Dir.mktmpdir('shim_compliance_')

    ok = system('ruby', @harness, 'openssl', @openssl_dir)
    raise "openssl harness failed (exit #{$CHILD_STATUS.exitstatus})" unless ok

    ok = system('ruby', '-I', File.join(@project_root, 'lib'), @harness, 'shim', @shim_dir)
    raise "shim harness failed (exit #{$CHILD_STATUS.exitstatus})" unless ok
  end

  after(:context) do
    FileUtils.rm_rf(@openssl_dir) if @openssl_dir
    FileUtils.rm_rf(@shim_dir) if @shim_dir
  end

  # Dynamically generate one example per output file.
  # We list the expected files explicitly so a missing file is a failure,
  # not a silent skip.
  # NOTE: ec_key_priv_* and ec_key_pub_* were removed in the A4 crypto
  # hardening pass (HLR #316). The DER-parsing BSVShimEC constructor was
  # deleted as dead code; the integration harness no longer generates
  # those output files.
  expected_files = %w[
    group_order.bin
    group_generator_compressed.bin
    group_generator_uncompressed.bin
    mul_g_1_compressed.bin
    mul_g_1_uncompressed.bin
    mul_g_mid_compressed.bin
    mul_g_mid_uncompressed.bin
    mul_g_high_compressed.bin
    mul_g_high_uncompressed.bin
    mul_nongen_compressed.bin
    mul_nongen_uncompressed.bin
    add_1_mid_compressed.bin
    add_mid_high_compressed.bin
    add_1_high_infinity.txt
    point_x_1.bin
    point_x_mid.bin
    to_bn_compressed_1.bin
    to_bn_compressed_mid.bin
    to_bn_hex_1.txt
    to_bn_hex_mid.txt
  ]

  expected_files.each do |filename|
    it "#{filename} is byte-identical between openssl and shim" do
      openssl_path = File.join(@openssl_dir, filename)
      shim_path    = File.join(@shim_dir, filename)

      expect(File.exist?(openssl_path)).to be(true), "openssl output missing: #{filename}"
      expect(File.exist?(shim_path)).to be(true), "shim output missing: #{filename}"

      openssl_md5 = Digest::MD5.file(openssl_path).hexdigest
      shim_md5    = Digest::MD5.file(shim_path).hexdigest

      expect(shim_md5).to eq(openssl_md5),
                          "MD5 mismatch for #{filename}:\n  openssl: #{openssl_md5}\n  shim:    #{shim_md5}"
    end
  end
end
# rubocop:enable RSpec/InstanceVariable, RSpec/BeforeAfterAll
