# frozen_string_literal: true

module BSV
  # Overlay Services module for BSV blockchain.
  #
  # Provides foundation types, protocol constants, and error classes for
  # interacting with BSV Overlay Services via the SHIP and SLAP protocols.
  module Overlay
    autoload :Constants,              'bsv/overlay/constants'
    autoload :TaggedBEEF,             'bsv/overlay/types'
    autoload :AdmittanceInstructions, 'bsv/overlay/types'
    autoload :LookupQuestion,         'bsv/overlay/types'
    autoload :LookupAnswer,           'bsv/overlay/types'
    autoload :OverlayBroadcastResult, 'bsv/overlay/types'
    autoload :OverlayError,           'bsv/overlay/errors'
    autoload :NoCompetentHostsError,  'bsv/overlay/errors'
    autoload :AllHostsRejectedError,  'bsv/overlay/errors'
    autoload :AcknowledgementError, 'bsv/overlay/errors'
    autoload :HostReputationTracker,    'bsv/overlay/host_reputation_tracker'
    autoload :AdminTokenTemplate,       'bsv/overlay/admin_token_template'
    autoload :LookupFacilitator,        'bsv/overlay/lookup_facilitator'
    autoload :HTTPSLookupFacilitator,   'bsv/overlay/lookup_facilitator'
    autoload :LookupResolver,           'bsv/overlay/lookup_resolver'
    autoload :BroadcastFacilitator,       'bsv/overlay/broadcast_facilitator'
    autoload :HTTPSBroadcastFacilitator,  'bsv/overlay/broadcast_facilitator'
    autoload :TopicBroadcaster,           'bsv/overlay/topic_broadcaster'
    autoload :SHIPBroadcaster,            'bsv/overlay/topic_broadcaster'
    autoload :Historian,                  'bsv/overlay/historian'
  end
end
