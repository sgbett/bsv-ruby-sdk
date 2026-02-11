# frozen_string_literal: true

module BSV
  module Script
    autoload :Opcodes, 'bsv/script/opcodes'
    autoload :Chunk,   'bsv/script/chunk'
    autoload :Builder, 'bsv/script/builder'
    autoload :Script,  'bsv/script/script'

    autoload :Interpreter,  'bsv/script/interpreter/interpreter'
    autoload :ScriptError,  'bsv/script/interpreter/error'
    autoload :ScriptNumber, 'bsv/script/interpreter/script_number'
    autoload :Stack,        'bsv/script/interpreter/stack'
  end
end
