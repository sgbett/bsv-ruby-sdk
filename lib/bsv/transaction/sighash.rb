# frozen_string_literal: true

module BSV
  module Transaction
    # Sighash type constants for BIP-143 transaction signing.
    #
    # BSV requires the +FORK_ID+ flag (0x40) on all sighash types. The
    # pre-combined constants (e.g. +ALL_FORK_ID+) are the most common
    # values used when signing transactions.
    module Sighash
      # Sign all inputs and all outputs.
      ALL             = 0x01

      # Sign all inputs, no outputs (outputs can be modified).
      NONE            = 0x02

      # Sign all inputs and only the output at the same index.
      SINGLE          = 0x03

      # Sign only this input (others can be added/removed).
      ANYONE_CAN_PAY  = 0x80

      # BSV fork ID flag (required on all BSV signatures).
      FORK_ID         = 0x40

      # Mask for extracting the base sighash type (ALL/NONE/SINGLE).
      MASK            = 0x1f

      # SIGHASH_ALL with FORKID — the default sighash type.
      ALL_FORK_ID     = ALL | FORK_ID             # 0x41

      # SIGHASH_NONE with FORKID.
      NONE_FORK_ID    = NONE | FORK_ID            # 0x42

      # SIGHASH_SINGLE with FORKID.
      SINGLE_FORK_ID  = SINGLE | FORK_ID          # 0x43

      # SIGHASH_ALL | ANYONE_CAN_PAY with FORKID.
      ALL_FORK_ID_ANYONE_CAN_PAY    = ALL_FORK_ID | ANYONE_CAN_PAY    # 0xC1

      # SIGHASH_NONE | ANYONE_CAN_PAY with FORKID.
      NONE_FORK_ID_ANYONE_CAN_PAY   = NONE_FORK_ID | ANYONE_CAN_PAY   # 0xC2

      # SIGHASH_SINGLE | ANYONE_CAN_PAY with FORKID.
      SINGLE_FORK_ID_ANYONE_CAN_PAY = SINGLE_FORK_ID | ANYONE_CAN_PAY # 0xC3
    end
  end
end
