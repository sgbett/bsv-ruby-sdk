# frozen_string_literal: true

module BSV
  module KVStore
    autoload :Interpreter, 'bsv/kv_store/interpreter'
    autoload :Entry,       'bsv/kv_store/entry'
    autoload :Token,       'bsv/kv_store/token'
    autoload :Global,      'bsv/kv_store/global'
  end
end
