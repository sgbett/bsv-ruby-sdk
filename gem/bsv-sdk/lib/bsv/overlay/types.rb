# frozen_string_literal: true

module BSV
  module Overlay
    # Tagged BEEF (Background Evaluation Extended Format) structure.
    #
    # Comprises a transaction, its SPV information, and the overlay topics
    # where its inclusion is requested.
    class TaggedBEEF
      # @return [String] raw binary BEEF-encoded transaction data
      attr_reader :beef

      # @return [Array<String>] overlay topic names where the transaction is to be submitted
      attr_reader :topics

      # @param beef [String] raw binary BEEF-encoded transaction data
      # @param topics [Array<String>] overlay topic names
      def initialize(beef:, topics:)
        @beef = beef
        @topics = topics
      end
    end

    # Instructs the Overlay Services Engine about which outputs to admit and
    # which previous outputs to retain. Returned by a Topic Manager.
    class AdmittanceInstructions
      # @return [Array<Integer>] indices of admissible outputs in the managed topic
      attr_reader :outputs_to_admit

      # @return [Array<Integer>] indices of inputs spending previously-admitted outputs to retain
      attr_reader :coins_to_retain

      # @return [Array<Integer>, nil] indices of inputs spending previously-admitted outputs
      #   that are now considered spent and removed from the topic (optional)
      attr_reader :coins_removed

      # @param outputs_to_admit [Array<Integer>]
      # @param coins_to_retain [Array<Integer>]
      # @param coins_removed [Array<Integer>, nil]
      def initialize(outputs_to_admit:, coins_to_retain:, coins_removed: nil)
        @outputs_to_admit = outputs_to_admit
        @coins_to_retain = coins_to_retain
        @coins_removed = coins_removed
      end
    end

    # The question asked to the Overlay Services Engine when a consumer of state
    # wishes to look up information.
    class LookupQuestion
      # @return [String] identifier of the Lookup Service to query
      attr_reader :service

      # @return [Hash] query forwarded to the Lookup Service; structure depends on the service
      attr_reader :query

      # @param service [String]
      # @param query [Hash]
      def initialize(service:, query:)
        @service = service
        @query = query
      end
    end

    # How the Overlay Services Engine responds to a LookupQuestion.
    class LookupAnswer
      # @return [String] response type (e.g. 'output-list')
      attr_reader :type

      # @return [Array] outputs or freeform response data from the Lookup Service
      attr_reader :outputs

      # @param type [String]
      # @param outputs [Array]
      def initialize(type:, outputs:)
        @type = type
        @outputs = outputs
      end
    end

    # Result of broadcasting a transaction to an Overlay Services host.
    class OverlayBroadcastResult
      # @return [String] result status ('success' or 'error')
      attr_reader :status

      # Overlay API boundary: display-order hex txid echoed from the broadcast response.
      # @return [String, nil] transaction identifier (present on success)
      attr_reader :txid

      # @return [String, nil] human-readable result message
      attr_reader :message

      # @return [String, nil] machine-readable error code
      attr_reader :code

      # @return [String, nil] human-readable error description
      attr_reader :description

      # @param status [String]
      # @param txid [String, nil]
      # @param message [String, nil]
      # @param code [String, nil]
      # @param description [String, nil]
      def initialize(status:, txid: nil, message: nil, code: nil, description: nil)
        @status = status
        BSV::Primitives::Hex.validate_dtxid_hex!(txid, name: 'overlay broadcast txid') if txid
        @txid = txid
        @message = message
        @code = code
        @description = description
      end
    end
  end
end
