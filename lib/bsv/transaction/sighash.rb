# frozen_string_literal: true

module BSV
  module Transaction
    module Sighash
      ALL             = 0x01
      NONE            = 0x02
      SINGLE          = 0x03
      ANYONE_CAN_PAY  = 0x80
      FORK_ID         = 0x40
      MASK            = 0x1f

      ALL_FORK_ID     = ALL | FORK_ID             # 0x41
      NONE_FORK_ID    = NONE | FORK_ID            # 0x42
      SINGLE_FORK_ID  = SINGLE | FORK_ID          # 0x43

      ALL_FORK_ID_ANYONE_CAN_PAY    = ALL_FORK_ID | ANYONE_CAN_PAY    # 0xC1
      NONE_FORK_ID_ANYONE_CAN_PAY   = NONE_FORK_ID | ANYONE_CAN_PAY   # 0xC2
      SINGLE_FORK_ID_ANYONE_CAN_PAY = SINGLE_FORK_ID | ANYONE_CAN_PAY # 0xC3
    end
  end
end
