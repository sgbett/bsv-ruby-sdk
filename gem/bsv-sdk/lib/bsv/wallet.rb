# frozen_string_literal: true

module BSV
  module Wallet
    # All files are loaded eagerly to avoid load-path collisions when bsv-wallet
    # is also present in the bundle (both gems share the bsv/wallet/* namespace).
    require_relative 'wallet/errors'
    require_relative 'wallet/validators'
    require_relative 'wallet/key_deriver'
    require_relative 'wallet/proto_wallet'
  end
end
