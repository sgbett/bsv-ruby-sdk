# frozen_string_literal: true

module BSV
  module Wallet
    module Interface
      # Duck-typed UTXO pool interface for managing pre-funded outputs.
      #
      # Include this module in pool implementations and override all instance
      # methods that raise +NotImplementedError+.
      module UTXOPool
        MAX_RETRIES = 3

        def acquire
          raise NotImplementedError, "#{self.class}#acquire not implemented"
        end

        def release(_outpoint)
          raise NotImplementedError, "#{self.class}#release not implemented"
        end

        def status
          raise NotImplementedError, "#{self.class}#status not implemented"
        end

        def shutdown
          raise NotImplementedError, "#{self.class}#shutdown not implemented"
        end
      end
    end
  end
end
