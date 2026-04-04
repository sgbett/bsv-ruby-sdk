# frozen_string_literal: true

require 'spec_helper'
require 'digest'
require 'tmpdir'

RSpec.describe 'OpenSSL EC Shim Integration (process-isolated)' do
  harness = File.expand_path('integration_harness.rb', __dir__)
  project_root = File.expand_path('../../..', __dir__)

  openssl_dir = Dir.mktmpdir('openssl_compliance_')
  shim_dir    = Dir.mktmpdir('shim_compliance_')

  # Run both backends in separate processes before any examples.
  # The openssl run uses raw ruby (no SDK). The shim run adds lib/ to the load path.
  before(:context) do
    ok = system('ruby', harness, 'openssl', openssl_dir)
    raise "openssl harness failed (exit #{$CHILD_STATUS.exitstatus})" unless ok

    ok = system('ruby', '-I', File.join(project_root, 'lib'), harness, 'shim', shim_dir)
    raise "shim harness failed (exit #{$CHILD_STATUS.exitstatus})" unless ok
  end

  after(:context) do
    FileUtils.rm_rf(openssl_dir)
    FileUtils.rm_rf(shim_dir)
  end

  # Dynamically generate one example per output file.
  # We list the expected files explicitly so a missing file is a failure,
  # not a silent skip.
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
    ec_key_priv_1.bin
    ec_key_priv_mid.bin
    ec_key_pub_compressed.bin
    ec_key_pub_uncompressed.bin
  ]

  expected_files.each do |filename|
    it "#{filename} is byte-identical between openssl and shim" do
      openssl_path = File.join(openssl_dir, filename)
      shim_path    = File.join(shim_dir, filename)

      expect(File.exist?(openssl_path)).to be(true), "openssl output missing: #{filename}"
      expect(File.exist?(shim_path)).to be(true), "shim output missing: #{filename}"

      openssl_md5 = Digest::MD5.file(openssl_path).hexdigest
      shim_md5    = Digest::MD5.file(shim_path).hexdigest

      expect(shim_md5).to eq(openssl_md5),
                          "MD5 mismatch for #{filename}:\n  openssl: #{openssl_md5}\n  shim:    #{shim_md5}"
    end
  end
end
