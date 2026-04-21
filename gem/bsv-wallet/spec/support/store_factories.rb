# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
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
  'FileStore' => lambda {
    dir = Dir.mktmpdir('bsv-wallet-test')
    Thread.current[:_bsv_wallet_tmpdir] = dir
    BSV::Wallet::Store::File.new(dir: dir)
  }
}.freeze

RSpec.configure do |config|
  config.after do
    dir = Thread.current[:_bsv_wallet_tmpdir]
    if dir && File.directory?(dir)
      FileUtils.rm_rf(dir)
      Thread.current[:_bsv_wallet_tmpdir] = nil
    end
  end
end
