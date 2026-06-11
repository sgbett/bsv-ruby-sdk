# frozen_string_literal: true

module BSV
  # Storage module for UHRP (Unified Hash Resource Protocol) URL encoding,
  # decoding, and validation helpers.
  #
  # UHRP enables content-addressed storage on BSV: a SHA-256 hash of a file
  # is Base58Check-encoded with the `\xCE\x00` prefix to produce a stable,
  # self-verifying URL.
  module Storage
    autoload :Utils, 'bsv/storage/utils'
  end
end
