# frozen_string_literal: true

require_relative 'bsv/version'

module BSV
  autoload :Primitives,  'bsv/primitives'
  autoload :Script,      'bsv/script'
  autoload :Transaction, 'bsv/transaction'
end
