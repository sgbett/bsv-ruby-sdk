# frozen_string_literal: true

module BSV
  module Storage
    # Raised when a UHRP file cannot be downloaded from any available host.
    class DownloadError < StandardError; end
  end
end
