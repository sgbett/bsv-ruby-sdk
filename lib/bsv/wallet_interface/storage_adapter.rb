# frozen_string_literal: true

module BSV
  module Wallet
    # Duck-typed storage interface for wallet persistence.
    #
    # Include this module in storage adapters and override all methods.
    # The default implementations raise NotImplementedError.
    module StorageAdapter
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
    end
  end
end
