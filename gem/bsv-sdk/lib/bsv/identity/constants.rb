# frozen_string_literal: true

module BSV
  module Identity
    # Protocol constants and well-known values for the BSV Identity system.
    module Constants
      # Overlay topic name for identity transactions.
      TOPIC = 'tm_identity'

      # Lookup service identifier for identity queries.
      SERVICE = 'ls_identity'

      # Maps symbolic names to their Base64-encoded 32-byte certificate type identifiers.
      #
      # Values are byte-exact matches with the TS SDK (ts-sdk/src/identity/types/index.ts)
      # and Go SDK (go-sdk/identity/types.go).
      KNOWN_IDENTITY_TYPES = {
        x_cert: 'vdDWvftf1H+5+ZprUw123kjHlywH+v20aPQTuXgMpNc=',
        discord_cert: '2TgqRC35B1zehGmB21xveZNc7i5iqHc0uxMb+1NMPW4=',
        phone_cert: 'mffUklUzxbHr65xLohn0hRL0Tq2GjW1GYF/OPfzqJ6A=',
        email_cert: 'exOl3KM0dIJ04EW5pZgbZmPag6MdJXd3/a1enmUU/BA=',
        identi_cert: 'z40BOInXkI8m7f/wBrv4MJ09bZfzZbTj2fJqCtONqCY=',
        registrant: 'YoPsbfR6YQczjzPdHCoGC7nJsOdPQR50+SYqcWpJ0y0=',
        cool_cert: 'AGfk/WrT1eBDXpz3mcw386Zww2HmqcIn3uY6x4Af1eo=',
        anyone: 'mfkOMfLDQmrr3SBxBQ5WeE+6Hy3VJRFq6w4A5Ljtlis=',
        self: 'Hkge6X5JRxt1cWXtHLCrSTg6dCVTxjQJJ48iOYd7n3g='
      }.freeze

      # Fallback identity used when no verified identity information is available.
      DEFAULT_IDENTITY = DisplayableIdentity.new(
        name: 'Unknown Identity',
        avatar_url: 'XUUB8bbn9fEthk15Ge3zTQXypUShfC94vFjp65v7u5CQ8qkpxzst',
        abbreviated_key: '',
        identity_key: '',
        badge_icon_url: 'XUUV39HVPkpmMzYNTx7rpKzJvXfeiVyQWg2vfSpjBAuhunTCA9uG',
        badge_label: 'Not verified by anyone you trust.',
        badge_click_url: 'https://projectbabbage.com/docs/unknown-identity'
      ).freeze
    end
  end
end
