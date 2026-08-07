# frozen_string_literal: true

module BSV
  module Primitives
    # Shared finite field arithmetic helpers.
    #
    # Included by classes that perform modular arithmetic (e.g.
    # PointInFiniteField, Polynomial) to avoid duplicating the same
    # utility methods.
    module FieldMath
      private

      # Unsigned modulo — always returns a non-negative result in [0, m).
      #
      # Ruby's +%+ can return a negative value when +n+ is negative;
      # this corrects for that.
      def umod(n, m)
        result = n % m
        result.negative? ? result + m : result
      end
    end
  end
end
