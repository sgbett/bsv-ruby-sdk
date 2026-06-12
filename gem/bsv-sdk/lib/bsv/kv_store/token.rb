# frozen_string_literal: true

module BSV
  module KVStore
    # Transaction output reference for a KVStore token.
    #
    # Populated when +include_token: true+ is passed to {Global#get}.
    Token = Data.define(:dtxid, :output_index, :beef, :satoshis)
  end
end
