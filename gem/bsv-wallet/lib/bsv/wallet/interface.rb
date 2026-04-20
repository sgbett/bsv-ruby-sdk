# frozen_string_literal: true

module BSV
  module Wallet
    # BRC-100 Wallet Interface
    #
    # Composes all 28 BRC-100 wallet methods from the {BRC100::Interface} sub-modules.
    # Include this module and override the methods your implementation supports.
    # Unimplemented methods raise {UnsupportedActionError}.
    module Interface
      include BRC100::Interface
    end
  end
end
