# frozen_string_literal: true

# Bidirectional in-process transport for testing.
#
# Connects two peers so that +send+ on one delivers to the other's
# +on_data+ callback. Wire two instances together via {.create_pair}.
#
# @example
#   transport_a, transport_b = PairedTransport.create_pair
#   peer_a = BSV::Auth::Peer.new(wallet: wallet_a, transport: transport_a)
#   peer_b = BSV::Auth::Peer.new(wallet: wallet_b, transport: transport_b)
class PairedTransport
  include BSV::Auth::Transport

  attr_accessor :partner

  def initialize
    @on_data_callback = nil
    @partner = nil
  end

  # Creates a pair of transports wired together bidirectionally.
  #
  # @return [Array<PairedTransport>] two connected transports [a, b]
  def self.create_pair
    a = new
    b = new
    a.partner = b
    b.partner = a
    [a, b]
  end

  # Sends +message+ to the partner transport's +on_data+ callback.
  #
  # @param message [Hash] the auth message to deliver
  # @raise [RuntimeError] if no partner has been set
  def send(message)
    raise 'PairedTransport has no partner' unless @partner

    @partner.deliver(message)
  end

  # Registers a callback invoked when a message is delivered to this transport.
  #
  # @yieldparam message [Hash] the incoming auth message
  def on_data(&block)
    @on_data_callback = block
  end

  # Delivers +message+ directly to this transport's +on_data+ callback.
  # Silently drops the message if no callback is registered.
  #
  # @param message [Hash] the incoming auth message
  def deliver(message)
    @on_data_callback&.call(message)
  end
end
