# frozen_string_literal: true

module BSV
  module Network
    # Protocols is a namespace module for concrete Protocol subclasses.
    # Each class maps a service's commands to HTTP endpoints: ARC, Chaintracks,
    # JungleBus, Ordinals, TAALBinary, and WoCREST.
    module Protocols
      autoload :ARC,         'bsv/network/protocols/arc'
      autoload :Chaintracks, 'bsv/network/protocols/chaintracks'
      autoload :JungleBus,   'bsv/network/protocols/jungle_bus'
      autoload :Ordinals,    'bsv/network/protocols/ordinals'
      autoload :TAALBinary,  'bsv/network/protocols/taal_binary'
      autoload :WoCREST,     'bsv/network/protocols/woc_rest'
    end
  end
end
