# frozen_string_literal: true

require 'net/http'

# Stubs +Net::HTTP.start+ with a recorder, so specs can assert which hosts a
# code path contacts and what credentials it sends them, without any network
# access (WebMock is not available).
#
# Each host is given a responder: a callable receiving the request and
# returning +[status, body]+. A request to any other host is recorded as
# unexpected and raises.
#
#   recorder = stub_net_http('arc.example.com' => ->(_req) { [200, '{}'] })
#   # ... exercise the code ...
#   recorder.hosts                      # => ['arc.example.com']
#   recorder.authorisation_for(host)    # => ['Bearer ...']
class NetHttpRecorder
  # Raised for a request to a host the spec did not expect.
  class UnexpectedHost < StandardError; end

  Entry = Struct.new(:host, :path, :authorization, :request)

  # A stand-in for the connection yielded by +Net::HTTP.start+.
  class Connection
    include FakeHttpResponse

    def initialize(recorder, host)
      @recorder = recorder
      @host = host
    end

    def request(req)
      @recorder.respond(@host, req)
    end
  end

  attr_reader :entries, :unexpected_hosts

  # @param responders [Hash{String => #call}] host => callable(request) -> [status, body]
  def initialize(responders)
    @responders = responders
    @entries = []
    @unexpected_hosts = []
  end

  def connect(host)
    unless @responders.key?(host)
      @unexpected_hosts << host
      raise UnexpectedHost, "unexpected request to #{host}"
    end

    Connection.new(self, host)
  end

  def respond(host, req)
    @entries << Entry.new(host, req.path, req['Authorization'], req)
    status, body = @responders.fetch(host).call(req)
    FakeHttpResponse.fake_http_response(status, body)
  end

  def hosts
    @entries.map(&:host).uniq
  end

  def entries_for(host)
    @entries.select { |entry| entry.host == host }
  end

  def authorisation_for(host)
    entries_for(host).map(&:authorization)
  end
end

module NetHttpStubbing
  # @param responders [Hash{String => #call}]
  # @return [NetHttpRecorder]
  def stub_net_http(responders)
    recorder = NetHttpRecorder.new(responders)
    allow(Net::HTTP).to receive(:start) do |host, _port, **_opts, &block|
      block.call(recorder.connect(host))
    end
    recorder
  end
end

RSpec.configure do |config|
  config.include NetHttpStubbing
end
