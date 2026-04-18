# frozen_string_literal: true

module BSV
  module Network
    # Registers all standard BSV network commands.
    #
    # Commands are registered eagerly when this file is required. Each command
    # describes a discrete network operation: its accepted parameters (as
    # documentation metadata) and the shape of its return value.
    #
    # Providers implement these commands via +call_<name>+ instance methods.
    # See {BSV::Network::Provider} for the dispatch mechanism.

    Command.define(
      :broadcast,
      params: { tx: 'Transaction' },
      returns: '{ txid: String, status: String, extra_info: Hash }',
      description: 'Submit a single transaction to the network via ARC'
    )

    Command.define(
      :broadcast_many,
      params: { txs: 'Array<Transaction>' },
      returns: 'Array<{ txid: String, status: String } | Error>',
      description: 'Submit multiple transactions to the network via ARC in a single request'
    )

    Command.define(
      :get_tx,
      params: { txid: 'String' },
      returns: 'String (raw hex)',
      description: 'Fetch a raw transaction by its TXID'
    )

    Command.define(
      :get_tx_status,
      params: { txid: 'String' },
      returns: '{ txid: String, tx_status: String, block_hash: String, block_height: Integer }',
      description: 'Fetch the ARC broadcast status of a transaction'
    )

    Command.define(
      :get_utxos,
      params: { address: 'String' },
      returns: 'Array<{ tx_hash: String, tx_pos: Integer, satoshis: Integer, height: Integer }>',
      description: 'Fetch all unspent outputs for a given address'
    )

    Command.define(
      :is_utxo,
      params: { txid: 'String', vout: 'Integer', script_hash: 'String (optional)' },
      returns: 'Boolean',
      description: 'Check whether a given outpoint is unspent. ' \
                   'Provide script_hash: for a single HTTP call; ' \
                   'omit it to trigger a two-call fallback (fetch tx, compute hash, then check).'
    )

    Command.define(
      :get_merkle_path,
      params: { txid: 'String' },
      returns: 'Hash (TSC proof components: { index:, tx_or_id:, target:, nodes: })',
      description: 'Fetch the TSC Merkle proof for a confirmed transaction. ' \
                   'Returns raw proof components — the caller must supply block_height ' \
                   'when converting to a MerklePath object.'
    )

    Command.define(
      :valid_root,
      params: { root: 'String', height: 'Integer' },
      returns: 'Boolean',
      description: 'Verify that a Merkle root matches the block header at a given height'
    )

    Command.define(
      :current_height,
      params: {},
      returns: 'Integer',
      description: 'Return the current best-chain block height'
    )

    Command.define(
      :get_script_unspent,
      params: { script_hash: 'String' },
      returns: 'Array<{ tx_hash: String, tx_pos: Integer, satoshis: Integer, height: Integer }>',
      description: 'Fetch all unspent outputs for a given script hash (SHA-256 of locking script)'
    )

    Command.define(
      :get_policy,
      params: {},
      returns: '{ policy: Hash }',
      description: 'Fetch the current ARC miner policy (fee rates, script limits, etc.)'
    )
  end
end
