# frozen_string_literal: true

module BSV
  # Bitcoin script parsing, construction, and execution.
  #
  # Provides the {Script::Script} class for building and inspecting scripts,
  # the {Script::Opcodes} module defining all opcodes, a fluent {Script::Builder},
  # and a full {Script::Interpreter} for script evaluation.
  module Script
    autoload :Opcodes, 'bsv/script/opcodes'
    autoload :Chunk,   'bsv/script/chunk'
    autoload :Builder, 'bsv/script/builder'
    autoload :Script,  'bsv/script/script'

    autoload :Interpreter,       'bsv/script/interpreter/interpreter'
    autoload :ScriptError,       'bsv/script/interpreter/error'
    autoload :ScriptNumber,      'bsv/script/interpreter/script_number'
    autoload :Stack,             'bsv/script/interpreter/stack'

    autoload :PushDropTemplate, 'bsv/script/push_drop_template'
    autoload :BIP276,           'bsv/script/bip276'
  end
end
