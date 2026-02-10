# frozen_string_literal: true

module BSV
  module Transaction
    class UnlockingScriptTemplate
      def sign(_tx, _input_index)
        raise NotImplementedError, "#{self.class}#sign must be implemented"
      end

      def estimated_length(_tx, _input_index)
        raise NotImplementedError, "#{self.class}#estimated_length must be implemented"
      end
    end
  end
end
