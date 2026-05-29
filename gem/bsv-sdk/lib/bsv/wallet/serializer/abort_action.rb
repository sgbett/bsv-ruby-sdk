# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +abort_action+ call (call byte 3).
      #
      # Args wire layout:
      #   [remaining bytes: reference (raw binary)]
      #
      # Result wire layout:
      #   [empty — success is implicit from the frame error byte]
      module AbortAction
        module_function

        def serialize_args(args)
          ref = args[:reference]
          return ''.b if ref.nil? || ref.empty?

          ref.b
        end

        def deserialize_args(bytes)
          ref = bytes.b
          { reference: ref.empty? ? nil : ref }
        end

        def serialize_result(_result)
          ''.b
        end

        def deserialize_result(_bytes)
          { aborted: true }
        end
      end
    end
  end
end
