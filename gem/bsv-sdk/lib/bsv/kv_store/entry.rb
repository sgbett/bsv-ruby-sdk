# frozen_string_literal: true

module BSV
  module KVStore
    # An immutable KVStore entry returned from {Global#get}.
    #
    # +token+ is populated only when +include_token: true+ is passed to +#get+.
    # +history+ is populated only when +history: true+ is passed to +#get+.
    Entry = Data.define(:key, :value, :controller, :protocol_id, :tags, :token, :history) do
      def initialize(key:, value:, controller:, protocol_id:, tags:, token: nil, history: nil)
        super
      end
    end
  end
end
