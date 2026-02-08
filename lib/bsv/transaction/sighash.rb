# frozen_string_literal: true

module BSV
  module Transaction
    module Sighash
      ALL             = 0x01
      NONE            = 0x02
      SINGLE          = 0x03
      ANYONE_CAN_PAY  = 0x80
      FORK_ID         = 0x40
      ALL_FORK_ID     = ALL | FORK_ID # 0x41
    end
  end
end
