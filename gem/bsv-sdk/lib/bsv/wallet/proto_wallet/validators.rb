# frozen_string_literal: true

module BSV
  module Wallet
    class ProtoWallet
      # Validation helpers for BRC-100 wallet method parameters.
      #
      # Delegates to Wire::Validation — the single source of truth for all
      # BRC-100 parameter validation. This module is retained for backwards
      # compatibility with ProtoWallet's internal call sites.
      module Validators
        module_function

        def validate_protocol_id!(protocol_id)
          Wire::Validation.wallet_protocol!('protocol_id', protocol_id)
        end

        def validate_key_id!(key_id)
          Wire::Validation.key_id_string_1_to_800!('key_id', key_id)
        end

        def validate_counterparty!(counterparty)
          Wire::Validation.wallet_counterparty!('counterparty', counterparty)
        end

        def validate_pub_key_hex!(value, name = 'public_key')
          Wire::Validation.pub_key_hex!(name, value)
        end
      end
    end
  end
end
