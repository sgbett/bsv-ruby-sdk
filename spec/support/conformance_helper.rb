# frozen_string_literal: true

# Shared context for protocol conformance specs.
#
# These specs are derived from the BSV Hub protocol documentation
# (https://hub.bsvblockchain.org/bitcoin-protocol-documentation),
# not from implementation logic. They verify that the SDK's behaviour
# matches the canonical protocol as documented by the BSV Association.
#
# Run all conformance specs independently:
#   bundle exec rspec spec/conformance/
#
# Filter by metadata tag:
#   bundle exec rspec --tag conformance

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/conformance/}) do |meta|
    meta[:conformance] = true
  end
end
