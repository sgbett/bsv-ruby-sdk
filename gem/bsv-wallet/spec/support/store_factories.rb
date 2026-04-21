# frozen_string_literal: true

require 'tmpdir'
require 'bsv/wallet/store/memory'

# Provides store factory methods for running specs against multiple
# storage backends. Each factory returns a fresh, isolated store instance.
#
# Usage in specs:
#
#   STORE_FACTORIES.each do |label, factory|
#     context "with #{label}" do
#       let(:storage) { factory.call }
#       # ... your examples ...
#     end
#   end
STORE_FACTORIES = {
  'MemoryStore' => -> { BSV::Wallet::Store::Memory.new },
  'FileStore'   => -> { BSV::Wallet::Store::File.new(dir: Dir.mktmpdir) }
}.freeze
