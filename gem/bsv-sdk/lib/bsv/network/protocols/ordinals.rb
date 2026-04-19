# frozen_string_literal: true

module BSV
  module Network
    module Protocols
      # Ordinals implements the GorillaPool Ordinals API as a Protocol subclass.
      #
      # Provides raw transaction hex lookup and Merkle path (proof) retrieval
      # via the GorillaPool Ordinals REST API. Pure DSL — no escape hatches needed.
      #
      # == Usage
      #
      #   ord = BSV::Network::Protocols::Ordinals.new(base_url: 'https://ordinals.gorillapool.io')
      #   result = ord.call(:get_tx, 'abc123...')
      #   result.data  # => "01000000..."  (raw hex string)
      #
      #   result = ord.call(:get_merkle_path, 'abc123...')
      #   result.data  # => { 'index' => 0, 'path' => [...] }
      class Ordinals < Protocol
        endpoint :get_tx,          :get, '/api/tx/{txid}/hex'
        endpoint :get_merkle_path, :get, '/api/tx/{txid}/proof', response: :json

        # @param base_url    [String] base URL for the Ordinals API
        # @param api_key     [String, nil] optional Bearer API key
        # @param http_client [Object, nil] injectable HTTP client for testing
        def initialize(base_url:, api_key: nil, http_client: nil)
          super
        end
      end
    end
  end
end
