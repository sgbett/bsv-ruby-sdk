# frozen_string_literal: true

module BSV
  module Overlay
    # Base error class for all Overlay Services errors.
    class OverlayError < StandardError; end

    # Raised when no overlay hosts are found that are competent to handle a request.
    class NoCompetentHostsError < OverlayError; end

    # Raised when all competent overlay hosts have rejected a broadcast.
    class AllHostsRejectedError < OverlayError; end

    # Raised when a host fails to acknowledge a submitted transaction as expected.
    class AcknowledgementError < OverlayError; end
  end
end
