# frozen_string_literal: true

module BSV
  module Wallet
    # In-memory storage adapter for testing.
    #
    # Stores actions, outputs, and certificates in plain Ruby arrays.
    # Not thread-safe; intended for test use only.
    class MemoryStore
      include StorageAdapter

      def initialize
        @actions = []
        @outputs = []
        @certificates = []
      end

      def store_action(action_data)
        @actions << action_data
        action_data
      end

      def find_actions(query)
        results = @actions
        if query[:labels]
          mode = query[:label_query_mode] || 'any'
          results = results.select do |a|
            action_labels = a[:labels] || []
            if mode == 'all'
              (query[:labels] - action_labels).empty?
            else
              (query[:labels] & action_labels).any?
            end
          end
        end
        apply_pagination(results, query)
      end

      def store_output(output_data)
        @outputs << output_data
        output_data
      end

      def find_outputs(query)
        results = @outputs
        results = results.select { |o| o[:basket] == query[:basket] } if query[:basket]
        if query[:tags]
          mode = query[:tag_query_mode] || 'any'
          results = results.select do |o|
            output_tags = o[:tags] || []
            if mode == 'all'
              (query[:tags] - output_tags).empty?
            else
              (query[:tags] & output_tags).any?
            end
          end
        end
        results = results.reject { |o| o[:spendable] == false } unless query[:include_spent]
        apply_pagination(results, query)
      end

      def delete_output(outpoint)
        idx = @outputs.index { |o| o[:outpoint] == outpoint }
        return false unless idx

        @outputs.delete_at(idx)
        true
      end

      def store_certificate(cert_data)
        @certificates << cert_data
        cert_data
      end

      def find_certificates(query)
        results = @certificates
        results = results.select { |c| query[:certifiers].include?(c[:certifier]) } if query[:certifiers]
        results = results.select { |c| query[:types].include?(c[:type]) } if query[:types]
        apply_pagination(results, query)
      end

      def delete_certificate(type:, serial_number:, certifier:)
        idx = @certificates.index do |c|
          c[:type] == type && c[:serial_number] == serial_number && c[:certifier] == certifier
        end
        return false unless idx

        @certificates.delete_at(idx)
        true
      end

      private

      def apply_pagination(results, query)
        offset = query[:offset] || 0
        limit = query[:limit] || 10
        results[offset, limit] || []
      end
    end
  end
end
