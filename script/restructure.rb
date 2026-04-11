#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot migration script: moves all gem source files from the flat
# lib/bsv/ layout into gem/<name>/lib/bsv/<module>/ directories.
#
# Usage:
#   ruby script/restructure.rb
#
# This script uses `git mv` so rename tracking is preserved.

require 'fileutils'

SDK_MODULES = %w[
  primitives script transaction network wallet
  auth overlay identity registry
].freeze

GEMS = {
  'bsv-sdk' => {
    entry: 'lib/bsv-sdk.rb',
    modules: SDK_MODULES.flat_map { |m| ["lib/bsv/#{m}.rb", "lib/bsv/#{m}"] },
    extras: ['lib/bsv/version.rb'],
    gemspec: 'bsv-sdk.gemspec',
    changelog: 'CHANGELOG-sdk.md',
    copy_readme: true
  },
  'bsv-wallet' => {
    entry: 'lib/bsv-wallet.rb',
    modules: ['lib/bsv/wallet_interface.rb', 'lib/bsv/wallet_interface'],
    extras: [],
    gemspec: 'bsv-wallet.gemspec',
    changelog: 'CHANGELOG-wallet.md'
  },
  'bsv-wallet-postgres' => {
    entry: 'lib/bsv-wallet-postgres.rb',
    modules: ['lib/bsv/wallet_postgres.rb', 'lib/bsv/wallet_postgres'],
    extras: [],
    gemspec: 'bsv-wallet-postgres.gemspec',
    changelog: 'CHANGELOG-wallet-postgres.md'
  },
  'bsv-attest' => {
    entry: 'lib/bsv-attest.rb',
    modules: ['lib/bsv/attest.rb', 'lib/bsv/attest'],
    extras: [],
    gemspec: 'bsv-attest.gemspec',
    changelog: 'CHANGELOG-attest.md'
  }
}.freeze

def run(cmd)
  puts "  #{cmd}"
  system(cmd) || abort("FAILED: #{cmd}")
end

GEMS.each do |name, config|
  gem_dir = "gem/#{name}"
  lib_dir = "#{gem_dir}/lib"
  bsv_dir = "#{lib_dir}/bsv"

  puts "\n=== #{name} ==="

  # Create target directories
  FileUtils.mkdir_p(bsv_dir)

  # Move entry point
  run "git mv #{config[:entry]} #{lib_dir}/"

  # Move module files and directories
  config[:modules].each do |src|
    if File.directory?(src)
      run "git mv #{src} #{bsv_dir}/"
    elsif File.exist?(src)
      run "git mv #{src} #{bsv_dir}/"
    else
      puts "  SKIP (not found): #{src}"
    end
  end

  # Move extras (version.rb etc.)
  config[:extras].each do |src|
    target_dir = File.dirname(src).sub('lib/', "#{lib_dir}/")
    FileUtils.mkdir_p(target_dir)
    run "git mv #{src} #{target_dir}/"
  end

  # Move gemspec
  run "git mv #{config[:gemspec]} #{gem_dir}/"

  # Move changelog (rename to CHANGELOG.md)
  run "git mv #{config[:changelog]} #{gem_dir}/CHANGELOG.md"

  # Copy LICENSE
  FileUtils.cp('LICENSE', "#{gem_dir}/LICENSE")
  run "git add #{gem_dir}/LICENSE"

  # Copy README for SDK only
  if config[:copy_readme]
    FileUtils.cp('README.md', "#{gem_dir}/README.md")
    run "git add #{gem_dir}/README.md"
  end
end

# Verify lib/ is now empty (only bsv/ dir which should be empty)
remaining = Dir.glob('lib/**/*').select { |f| File.file?(f) }
if remaining.empty?
  puts "\n✓ lib/ is now empty — removing"
  FileUtils.rm_rf('lib')
else
  puts "\n✗ lib/ still has files:"
  remaining.each { |f| puts "  #{f}" }
  abort 'Unexpected files remaining in lib/'
end

puts "\n=== Summary ==="
GEMS.each_key do |name|
  count = Dir.glob("gem/#{name}/lib/**/*").count { |f| File.file?(f) }
  puts "  gem/#{name}/lib/: #{count} files"
end
puts "\nDone. Run `git status` to review, then commit."
