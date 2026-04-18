# frozen_string_literal: true

module BSV
  module Network
    # Result module provides immutable value objects for network operation outcomes.
    #
    # Three distinct result types are provided:
    #   - Result::Success  — operation completed; carries optional data
    #   - Result::Error    — operation failed; carries message and retryable flag
    #   - Result::NotFound — resource does not exist; distinct from a transport error
    #
    # All types are frozen after initialisation and support value equality.
    module Result
      # Shared predicate defaults for result types.
      #
      # Each class overrides the one predicate that applies to it; the module
      # supplies the false defaults so callers can always call all three methods
      # on any result without a NoMethodError.
      module Predicates
        def success?
          false
        end

        def error?
          false
        end

        def not_found?
          false
        end
      end

      # Represents a successful operation outcome.
      class Success
        include Predicates

        attr_reader :data

        def initialize(data: nil)
          @data = data
          freeze
        end

        def success?
          true
        end

        def ==(other)
          other.is_a?(Success) && other.data == data
        end

        alias eql? ==

        def hash
          [self.class, data].hash
        end
      end

      # Represents a failed operation outcome.
      class Error
        include Predicates

        attr_reader :message, :retryable

        def initialize(message, retryable: false)
          @message = message
          @retryable = retryable
          freeze
        end

        def error?
          true
        end

        def retryable?
          !!retryable
        end

        def ==(other)
          other.is_a?(Error) && other.message == message && other.retryable == retryable
        end

        alias eql? ==

        def hash
          [self.class, message, retryable].hash
        end
      end

      # Represents a "resource not found" outcome — distinct from a transport error.
      class NotFound
        include Predicates

        def initialize
          freeze
        end

        def not_found?
          true
        end

        def ==(other)
          other.is_a?(NotFound)
        end

        alias eql? ==

        def hash
          self.class.hash
        end
      end
    end
  end
end
