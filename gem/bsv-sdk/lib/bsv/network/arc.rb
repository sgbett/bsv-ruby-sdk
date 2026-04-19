# frozen_string_literal: true

module BSV
  module Network
    # ARC broadcaster for submitting transactions to the BSV network.
    #
    # This facade preserves the legacy public API contract while delegating all
    # HTTP logic to +Protocols::ARC+. It translates +Result+ objects returned by
    # the protocol into +BroadcastResponse+ instances or raised +BroadcastError+
    # exceptions as required by consumer code.
    #
    # Any object responding to #broadcast(tx) can serve as a broadcaster;
    # this class implements that contract using the ARC API.
    class ARC
      # Returns an ARC instance pointed at the GorillaPool public ARC endpoint.
      #
      # @param testnet [Boolean] when true, uses the GorillaPool testnet endpoint
      # @param api_key [String, nil] optional bearer token for Authorization
      # @param http_client [#request, nil] injectable HTTP client for testing
      # @param opts [Hash] ARC-specific options forwarded to the protocol
      #   (e.g. +deployment_id:+, +callback_url:+, +callback_token:+)
      # @return [ARC]
      def self.default(testnet: false, api_key: nil, http_client: nil, **opts)
        provider = Providers::GorillaPool.default(testnet: testnet)
        arc_protocol = provider.protocol_for(:broadcast)
        base_url = arc_protocol.base_url
        new(
          base_url,
          api_key: api_key,
          http_client: http_client,
          **opts
        )
      end

      # ARC response statuses that indicate the transaction was NOT accepted.
      REJECTED_STATUSES = %w[
        REJECTED
        DOUBLE_SPEND_ATTEMPTED
        INVALID
        MALFORMED
        MINED_IN_STALE_BLOCK
      ].freeze

      # @param url_or_protocol [String, Protocols::ARC] ARC base URL (without
      #   trailing slash) or a pre-configured +Protocols::ARC+ instance. When a
      #   URL string is supplied, the remaining keyword arguments are forwarded to
      #   the underlying protocol constructor. When a protocol instance is supplied,
      #   all keyword arguments are ignored.
      # @param api_key [String, nil] optional bearer token for Authorization
      # @param deployment_id [String, nil] optional deployment identifier for
      #   the +XDeployment-ID+ header; defaults to a per-instance random value
      # @param callback_url [String, nil] optional +X-CallbackUrl+ for ARC
      #   status callbacks
      # @param callback_token [String, nil] optional +X-CallbackToken+ for
      #   ARC status callback authentication
      # @param http_client [#request, nil] injectable HTTP client for testing
      def initialize(url_or_protocol, api_key: nil, deployment_id: nil, callback_url: nil,
                     callback_token: nil, http_client: nil)
        @protocol =
          if url_or_protocol.is_a?(String)
            Protocols::ARC.new(
              base_url: url_or_protocol,
              api_key: api_key,
              deployment_id: deployment_id,
              callback_url: callback_url,
              callback_token: callback_token,
              http_client: http_client
            )
          else
            url_or_protocol
          end
      end

      # Submit a transaction to ARC.
      #
      # @param tx [Transaction] the transaction to broadcast
      # @param wait_for [String, nil] ARC wait condition
      # @param skip_fee_validation [Boolean, nil] when truthy, sends X-SkipFeeValidation header
      # @param skip_script_validation [Boolean, nil] when truthy, sends X-SkipScriptValidation header
      # @return [BroadcastResponse]
      # @raise [BroadcastError] when ARC returns a non-2xx HTTP status or a
      #   rejected/orphan +txStatus+
      def broadcast(tx, wait_for: nil, skip_fee_validation: nil, skip_script_validation: nil)
        result = @protocol.call(
          :broadcast, tx,
          wait_for: wait_for,
          skip_fee_validation: skip_fee_validation,
          skip_script_validation: skip_script_validation
        )
        result_to_response!(result)
      end

      # Submit multiple transactions to ARC in a single batch request.
      #
      # Returns a mixed array of {BroadcastResponse} and {BroadcastError} objects.
      # Per-transaction rejections are returned as {BroadcastError} values rather
      # than raised. Only HTTP-level errors raise a {BroadcastError} for the whole batch.
      #
      # @param txs [Array<Transaction>] transactions to broadcast
      # @param wait_for [String, nil] ARC wait condition
      # @param skip_fee_validation [Boolean, nil]
      # @param skip_script_validation [Boolean, nil]
      # @return [Array<BroadcastResponse, BroadcastError>]
      # @raise [BroadcastError] when ARC returns a non-2xx HTTP status
      def broadcast_many(txs, wait_for: nil, skip_fee_validation: nil, skip_script_validation: nil)
        result = @protocol.call(
          :broadcast_many, txs,
          wait_for: wait_for,
          skip_fee_validation: skip_fee_validation,
          skip_script_validation: skip_script_validation
        )

        case result
        when Result::Success
          result.data.map { |item| item_to_response_or_error(item) }
        else
          raise broadcast_error_from_result(result)
        end
      end

      # Query the status of a previously submitted transaction.
      #
      # @param txid [String] transaction ID to query
      # @return [BroadcastResponse]
      # @raise [BroadcastError] on failure
      def status(txid)
        result = @protocol.call(:get_tx_status, txid)
        result_to_response!(result)
      end

      private

      # Translate a single-tx Result into a BroadcastResponse or raise BroadcastError.
      def result_to_response!(result)
        case result
        when Result::Success
          BroadcastResponse.new(result.data)
        else
          raise broadcast_error_from_result(result)
        end
      end

      # Translate a per-item batch Result into a BroadcastResponse or BroadcastError
      # (returned, not raised).
      def item_to_response_or_error(item)
        case item
        when Result::Success
          BroadcastResponse.new(item.data)
        else
          broadcast_error_from_result(item)
        end
      end

      # Build a BroadcastError from a Result::Error or Result::NotFound.
      def broadcast_error_from_result(result)
        meta = result.metadata || {}
        BroadcastError.new(
          result.message,
          status_code: meta[:status_code],
          txid: meta[:txid],
          arc_status: meta[:arc_status]
        )
      end
    end
  end
end
