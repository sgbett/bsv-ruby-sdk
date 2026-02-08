# frozen_string_literal: true

module BSV
  module Transaction
    autoload :VarInt,            'bsv/transaction/var_int'
    autoload :TransactionOutput, 'bsv/transaction/transaction_output'
    autoload :TransactionInput,  'bsv/transaction/transaction_input'
    autoload :Sighash,           'bsv/transaction/sighash'
    autoload :Transaction,       'bsv/transaction/transaction'
  end
end
