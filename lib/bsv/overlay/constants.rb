# frozen_string_literal: true

module BSV
  module Overlay
    # Protocol identifiers and network configuration constants for BSV Overlay Services.
    module Constants
      # Short protocol identifier for Service Host Interconnect.
      PROTOCOL_SHIP = 'SHIP'

      # Short protocol identifier for Service Lookup Availability Protocol.
      PROTOCOL_SLAP = 'SLAP'

      # Full protocol identifier for Service Host Interconnect (display / human-readable form).
      PROTOCOL_ID_SHIP = 'Service Host Interconnect'

      # Full protocol identifier for Service Lookup Availability Protocol (display / human-readable form).
      PROTOCOL_ID_SLAP = 'Service Lookup Availability'

      # BRC-42/43 key-derivation protocol name for Service Host Interconnect.
      # Lowercase as required by the wallet key-derivation validator.
      DERIVE_PROTOCOL_SHIP = 'service host interconnect'

      # BRC-42/43 key-derivation protocol name for Service Lookup Availability.
      # Lowercase as required by the wallet key-derivation validator.
      DERIVE_PROTOCOL_SLAP = 'service lookup availability'

      # Default SLAP tracker URLs for mainnet.
      # These nodes maintain records of which overlay services are available and where.
      DEFAULT_SLAP_TRACKERS = [
        # BSVA clusters
        'https://overlay-us-1.bsvb.tech',
        'https://overlay-eu-1.bsvb.tech',
        'https://overlay-ap-1.bsvb.tech',

        # Babbage primary overlay service
        'https://users.bapp.dev'
      ].freeze

      # Default SLAP tracker URLs for testnet.
      DEFAULT_TESTNET_SLAP_TRACKERS = [
        # Babbage primary testnet overlay service
        'https://testnet-users.bapp.dev'
      ].freeze

      # Network presets mapping network names to their default SLAP tracker lists.
      NETWORK_PRESETS = {
        'mainnet' => DEFAULT_SLAP_TRACKERS,
        'testnet' => DEFAULT_TESTNET_SLAP_TRACKERS
      }.freeze
    end
  end
end
