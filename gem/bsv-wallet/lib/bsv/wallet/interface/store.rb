# frozen_string_literal: true

module BSV
  module Wallet
    module Interface
      # Duck-typed storage interface for wallet persistence.
      #
      # Include this module in storage adapters and override all methods.
      # The default implementations raise NotImplementedError.
      module Store
        def store_action(_action_data)
          raise NotImplementedError, "#{self.class}#store_action not implemented"
        end

        def find_actions(_query)
          raise NotImplementedError, "#{self.class}#find_actions not implemented"
        end

        def store_output(_output_data)
          raise NotImplementedError, "#{self.class}#store_output not implemented"
        end

        def find_outputs(_query)
          raise NotImplementedError, "#{self.class}#find_outputs not implemented"
        end

        def delete_output(_outpoint)
          raise NotImplementedError, "#{self.class}#delete_output not implemented"
        end

        def store_certificate(_cert_data)
          raise NotImplementedError, "#{self.class}#store_certificate not implemented"
        end

        def find_certificates(_query)
          raise NotImplementedError, "#{self.class}#find_certificates not implemented"
        end

        def delete_certificate(type:, serial_number:, certifier:)
          raise NotImplementedError, "#{self.class}#delete_certificate not implemented"
        end

        def count_actions(_query)
          raise NotImplementedError, "#{self.class}#count_actions not implemented"
        end

        def count_outputs(_query)
          raise NotImplementedError, "#{self.class}#count_outputs not implemented"
        end

        def count_certificates(_query)
          raise NotImplementedError, "#{self.class}#count_certificates not implemented"
        end

        def store_proof(_txid, _bump_hex)
          raise NotImplementedError, "#{self.class}#store_proof not implemented"
        end

        def find_proof(_txid)
          raise NotImplementedError, "#{self.class}#find_proof not implemented"
        end

        def store_transaction(_txid, _tx_hex)
          raise NotImplementedError, "#{self.class}#store_transaction not implemented"
        end

        def find_transaction(_txid)
          raise NotImplementedError, "#{self.class}#find_transaction not implemented"
        end

        def update_action_status(_txid, _new_status)
          raise NotImplementedError, "#{self.class}#update_action_status not implemented"
        end

        def delete_action(_txid)
          raise NotImplementedError, "#{self.class}#delete_action not implemented"
        end

        def update_output_basket(_outpoint, _new_basket)
          raise NotImplementedError, "#{self.class}#update_output_basket not implemented"
        end

        def update_output_state(_outpoint, _new_state, pending_reference: nil, no_send: nil)
          raise NotImplementedError, "#{self.class}#update_output_state not implemented"
        end

        def lock_utxos(_outpoints, reference:, no_send: false)
          raise NotImplementedError, "#{self.class}#lock_utxos not implemented"
        end

        def find_spendable_outputs(basket: nil, min_satoshis: nil, sort_order: :desc)
          raise NotImplementedError, "#{self.class}#find_spendable_outputs not implemented"
        end

        def release_stale_pending!(timeout: 300)
          raise NotImplementedError, "#{self.class}#release_stale_pending! not implemented"
        end

        def store_setting(_key, _value)
          raise NotImplementedError, "#{self.class}#store_setting not implemented"
        end

        def find_setting(_key)
          raise NotImplementedError, "#{self.class}#find_setting not implemented"
        end
      end
    end
  end
end
