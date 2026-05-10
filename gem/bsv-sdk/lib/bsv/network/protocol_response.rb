# frozen_string_literal: true

require 'net/http'

module BSV
  module Network
    class ProtocolResponse
      attr_reader :data, :error_message

      def initialize(http_response, data: nil, ok: nil, error_message: nil)
        @http_response = http_response
        @data = data
        @ok = ok.nil? ? http_response&.is_a?(Net::HTTPSuccess) : ok
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

      # Status predicates
      def success?
        @ok
      end

      def error?
        !@ok
      end

      def not_found?
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
        self.class.new(
          @http_response,
          data: overrides.fetch(:data, @data),
          ok: overrides.fetch(:ok, @ok),
          error_message: overrides.fetch(:error_message, @error_message)
        )
      end
    end
  end
end
