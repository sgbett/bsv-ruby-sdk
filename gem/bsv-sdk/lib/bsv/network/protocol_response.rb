# frozen_string_literal: true

require 'net/http'

module BSV
  module Network
    class ProtocolResponse
      attr_reader :data, :error_message

      def initialize(http_response, data: nil, http_success: nil, error_message: nil)
        @http_response = http_response
        @data = data
        @http_success = http_success.nil? ? http_response.is_a?(Net::HTTPSuccess) : http_success
        @error_message = error_message
        freeze
      end

      # Delegated from Net::HTTPResponse (nil-safe)
      def body
        @http_response&.body
      end

      def code
        @http_response&.code
      end

      def content_type
        @http_response&.content_type
      end

      # Two layers of status predicates:
      #
      # HTTP logical status — did the operation succeed? Driven by the +http_success:+
      # parameter, which defaults to the RFC 9110 success class check
      # (+Net::HTTPSuccess+, i.e. 2xx) but can be overridden by escape
      # hatches that reinterpret HTTP status (e.g. ARC REJECTED on 2xx
      # sets http_success: false; WoC is_utxo 404 sets http_success: true).
      #
      # Transport status — what did the HTTP layer actually return?
      # These always reflect the +Net::HTTPResponse+ class hierarchy
      # regardless of the +http_success:+ override. +http_not_found?+ maps
      # directly to +Net::HTTPNotFound+ (404). +retryable?+ is a
      # domain composite: 429 (+Net::HTTPTooManyRequests+) or 5xx
      # (+Net::HTTPServerError+) — not an RFC 9110 category itself,
      # but a useful signal for retry logic.

      def http_success?
        @http_success
      end

      def http_not_found?
        @http_response.is_a?(Net::HTTPNotFound)
      end

      def retryable?
        @http_response.is_a?(Net::HTTPTooManyRequests) ||
          @http_response.is_a?(Net::HTTPServerError)
      end

      # Canonical form (placeholder — delegates to data until shapes are defined)
      def canonical
        data
      end

      # Compatibility: chain trackers + MCP tools call .message
      alias message error_message

      # Derive new response with overrides (same HTTP response, different interpretation)
      def with(**overrides)
        derived = self.class.new(
          @http_response,
          data: overrides.fetch(:data, @data),
          http_success: overrides.fetch(:http_success, @http_success),
          error_message: overrides.fetch(:error_message, @error_message)
        )

        BSV.logger&.debug do
          changes = overrides.keys.map { |k| "#{k}=#{overrides[k].inspect[0, 40]}" }.join(' ')
          "[ProtocolResponse] with(#{changes})"
        end

        derived
      end
    end
  end
end
