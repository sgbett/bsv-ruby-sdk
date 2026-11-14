# frozen_string_literal: true

# Temporarily sets (or, with nil, removes) environment variables for the
# duration of a block, restoring the previous values afterwards.
module EnvHelper
  # The environment variables read by BSV::MCP::Config.
  MCP_ENV_VARS = %w[BSV_NETWORK BSV_ARC_URL BSV_ARC_API_KEY].freeze

  module_function

  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV.store(k, v) }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV.store(k, v) }
  end
end

RSpec.configure do |config|
  config.include EnvHelper

  # MCP specs must not depend on the developer's own BSV_* settings.
  config.around(:each, file_path: %r{/spec/bsv/mcp/}) do |example|
    EnvHelper.with_env(EnvHelper::MCP_ENV_VARS.to_h { |name| [name, nil] }) { example.run }
  end
end
