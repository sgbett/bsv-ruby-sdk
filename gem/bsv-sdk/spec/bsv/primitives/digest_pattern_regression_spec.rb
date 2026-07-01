# frozen_string_literal: true

require 'spec_helper'

# Regression guard for HLR #882 — digest context reuse.
#
# All direct OpenSSL::Digest:: calls in lib/ must live inside
# lib/bsv/primitives/digest.rb.  Any call outside that file bypasses the
# per-thread cache and reintroduces the EVP_get_digestbyname namemap cost
# that #882 eliminates.
#
# This spec fails if a future contributor adds a direct OpenSSL::Digest::
# instantiation anywhere else in the lib/ tree.  It runs on every `bundle
# exec rake` invocation (fast — pure grep, no digest computation).

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'OpenSSL::Digest:: bypass regression guard' do
  it 'has no direct OpenSSL::Digest:: calls in lib/ outside primitives/digest.rb' do
    lib_root = File.expand_path('../../../../../../lib', __dir__)
    digest_rb = File.join(lib_root, 'bsv', 'primitives', 'digest.rb')

    offenders = []

    Dir.glob("#{lib_root}/**/*.rb").each do |path|
      next if File.realpath(path) == File.realpath(digest_rb)

      File.foreach(path).with_index(1) do |line, lineno|
        offenders << "#{path}:#{lineno}: #{line.chomp}" if line.include?('OpenSSL::Digest::')
      end
    end

    expect(offenders).to be_empty,
                         'Found direct OpenSSL::Digest:: calls outside primitives/digest.rb — ' \
                         "route through BSV::Primitives::Digest instead:\n#{offenders.join("\n")}"
  end
end
# rubocop:enable RSpec/DescribeClass
