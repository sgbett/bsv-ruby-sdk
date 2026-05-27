# frozen_string_literal: true

module BSV
  module Wallet
    module Wire
      autoload :Frame,       'bsv/wallet/wire/frame'
      autoload :Calls,       'bsv/wallet/wire/calls'
      autoload :Validation,  'bsv/wallet/wire/validation'
      autoload :ReaderWriter, 'bsv/wallet/wire/reader_writer'
    end
  end
end
