# frozen_string_literal: true

module BSV
  module Wallet
    module Wire
      autoload :Frame,        'bsv/wallet/wire/frame'
      autoload :Calls,        'bsv/wallet/wire/calls'
      autoload :Validation,   'bsv/wallet/wire/validation'
      autoload :Writer,       'bsv/wallet/wire/reader_writer'
      autoload :Reader,       'bsv/wallet/wire/reader_writer'
    end
  end
end
