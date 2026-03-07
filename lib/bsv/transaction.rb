# frozen_string_literal: true

module BSV
  # Transaction building, signing, serialisation, and verification.
  #
  # Provides the {Transaction::Transaction} class for constructing and signing
  # transactions, {Transaction::Beef} for BEEF (BRC-62/95/96) serialisation,
  # {Transaction::MerklePath} for BRC-74 merkle proofs, and
  # {Transaction::Sighash} constants for BIP-143 sighash computation.
  module Transaction
    autoload :VarInt,            'bsv/transaction/var_int'
    autoload :TransactionOutput, 'bsv/transaction/transaction_output'
    autoload :TransactionInput,  'bsv/transaction/transaction_input'
    autoload :Sighash,           'bsv/transaction/sighash'
    autoload :MerklePath,        'bsv/transaction/merkle_path'
    autoload :FeeModel,                  'bsv/transaction/fee_model'
    autoload :FeeModels,                 'bsv/transaction/fee_models'
    autoload :ChainTracker,              'bsv/transaction/chain_tracker'
    autoload :ChainTrackers,             'bsv/transaction/chain_trackers'
    autoload :Beef,                      'bsv/transaction/beef'
    autoload :UnlockingScriptTemplate,   'bsv/transaction/unlocking_script_template'
    autoload :P2PKH,                     'bsv/transaction/p2pkh'
    autoload :Transaction,               'bsv/transaction/transaction'
  end
end
