# frozen_string_literal: true

module BSV
  module Registry
    # Protocol constants and well-known values for the BSV Registry system.
    #
    # Topic and service names match the TS SDK and Go SDK exactly.
    # Each definition type has its own topic/service/protocol/basket triplet
    # so overlay nodes can route and index them independently.
    module Constants
      # Overlay topic names — one per definition type.
      TOPIC_BASKET      = 'tm_basketmap'
      TOPIC_PROTOCOL    = 'tm_protomap'
      TOPIC_CERTIFICATE = 'tm_certmap'

      # Lookup service names — one per definition type.
      SERVICE_BASKET      = 'ls_basketmap'
      SERVICE_PROTOCOL    = 'ls_protomap'
      SERVICE_CERTIFICATE = 'ls_certmap'

      # BRC-43 wallet protocol IDs — one per definition type.
      # Security level 1 = every app and counterparty (matching TS/Go SDKs).
      PROTOCOL_BASKET      = [1, 'basketmap'].freeze
      PROTOCOL_PROTOCOL    = [1, 'protomap'].freeze
      PROTOCOL_CERTIFICATE = [1, 'certmap'].freeze

      # Basket names used when listing wallet outputs — one per definition type.
      BASKET_NAME_BASKET      = 'basketmap'
      BASKET_NAME_PROTOCOL    = 'protomap'
      BASKET_NAME_CERTIFICATE = 'certmap'

      # Key ID used for all PushDrop registry tokens (matches TS/Go SDKs).
      KEY_ID = '1'

      # Satoshi value of each registry UTXO token.
      TOKEN_AMOUNT = 1
    end
  end
end
