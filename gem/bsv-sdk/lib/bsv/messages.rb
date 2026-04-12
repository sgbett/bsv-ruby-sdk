# frozen_string_literal: true

module BSV
  # Namespace providing TS SDK naming parity for messaging primitives.
  #
  # Re-exports {BSV::Primitives::SignedMessage} and {BSV::Primitives::EncryptedMessage}
  # under the +BSV::Messages+ namespace, matching the structure of the TypeScript SDK
  # (ts-sdk/src/messages/index.ts).
  #
  # The canonical implementations remain in +BSV::Primitives+; this module is a
  # lightweight re-export only.
  module Messages
    SignedMessage = BSV::Primitives::SignedMessage
    EncryptedMessage = BSV::Primitives::EncryptedMessage
  end
end
