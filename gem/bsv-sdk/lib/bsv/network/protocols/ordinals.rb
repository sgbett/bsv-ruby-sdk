# frozen_string_literal: true

module BSV
  module Network
    module Protocols
      # Ordinals protocol adapter for the GorillaPool Ordinals service.
      #
      # Provides raw transaction hex lookup and Merkle path (proof) retrieval
      # via the GorillaPool Ordinals REST API.
      #
      # == Usage
      #
      #   ord = BSV::Network::Protocols::Ordinals.new(
      #     base_url: 'https://ordinals.gorillapool.io'
      #   )
      #   result = ord.call(:get_tx, txid: 'abc123...')
      #   result.data  # => "01000000..."  (raw hex string)
      #
      #   result = ord.call(:get_merkle_path, txid: 'abc123...')
      #   result.data  # => { 'index' => 0, 'path' => [...] }
      class Ordinals < BSV::Network::Protocol
        endpoint :get_tx,          :get, '/api/tx/{txid}/hex'
        endpoint :get_merkle_path, :get, '/api/tx/{txid}/proof', response: :json
      end
    end
  end
end
