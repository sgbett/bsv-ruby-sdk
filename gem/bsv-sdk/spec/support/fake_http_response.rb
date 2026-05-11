# frozen_string_literal: true

require 'net/http'

# Builds a properly-typed Net::HTTPResponse subclass instance for testing.
# Unlike Struct-based fakes, these pass is_a? checks against Net::HTTPSuccess,
# Net::HTTPNotFound, Net::HTTPServerError, etc.
module FakeHttpResponse
  module_function

  def fake_http_response(code, body, content_type: nil)
    klass = Net::HTTPResponse::CODE_TO_OBJ[code.to_s]
    raise ArgumentError, "unknown HTTP code: #{code}" unless klass

    response = klass.new('1.1', code.to_s, '')
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response['Content-Type'] = content_type if content_type
    response
  end
end

RSpec.configure do |config|
  config.include FakeHttpResponse
end
