# frozen_string_literal: true

module BSV
  module Network
    # Result module provides three immutable value types for Protocol dispatch outcomes.
    #
    # All three types share a Predicates mixin with default false implementations.
    # Each type overrides only the predicate that returns true for that type.
    module Result
      # Mixin providing default false implementations for all query predicates.
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

      # Represents a successful outcome. Carries the response payload in +data+
      # and optional protocol-specific extras in +metadata+.
      class Success
        include Predicates

        attr_reader :data, :metadata

        def initialize(data:, metadata: {})
          @data = data
          @metadata = metadata.freeze
          freeze
        end

        def success?
          true
        end

        def ==(other)
          other.is_a?(Success) && data == other.data && metadata == other.metadata
        end

        alias eql? ==

        def hash
          [self.class, data, metadata].hash
        end
      end

      # Represents a failed outcome. Carries a human-readable +message+, a boolean
      # +retryable+ flag indicating whether the caller should retry, and optional
      # +metadata+ for structured protocol-specific details (e.g. +arc_status+).
      class Error
        include Predicates

        attr_reader :message, :retryable, :metadata

        def initialize(message:, retryable: false, metadata: {})
          @message = message
          @retryable = retryable
          @metadata = metadata.freeze
          freeze
        end

        def error?
          true
        end

        def retryable?
          @retryable
        end

        def ==(other)
          other.is_a?(Error) &&
            message == other.message &&
            retryable == other.retryable &&
            metadata == other.metadata
        end

        alias eql? ==

        def hash
          [self.class, message, retryable, metadata].hash
        end
      end

      # Represents a resource-not-found outcome. Carries an optional human-readable
      # +message+ and optional +metadata+.
      class NotFound
        include Predicates

        attr_reader :message, :metadata

        def initialize(message: nil, metadata: {})
          @message = message
          @metadata = metadata.freeze
          freeze
        end

        def not_found?
          true
        end

        def ==(other)
          other.is_a?(NotFound) && message == other.message && metadata == other.metadata
        end

        alias eql? ==

        def hash
          [self.class, message, metadata].hash
        end
      end
    end
  end
end
