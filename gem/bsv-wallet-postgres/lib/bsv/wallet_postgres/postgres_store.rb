# frozen_string_literal: true

require 'sequel'
require 'sequel/extensions/migration'
require 'json'

module BSV
  module Wallet
    # PostgreSQL-backed storage adapter for +BSV::Wallet+.
    #
    # Implements the full {StorageAdapter} interface against a Sequel
    # +Database+ object. Survives process restarts, scales to multiple
    # instances, and is thread-safe via Sequel's connection pool.
    #
    # @example Quickstart
    #   require 'bsv-wallet-postgres'
    #
    #   db = Sequel.connect(ENV['DATABASE_URL'])
    #   BSV::Wallet::PostgresStore.migrate!(db)
    #
    #   store  = BSV::Wallet::PostgresStore.new(db)
    #   wallet = BSV::Wallet::WalletClient.new(key, storage: store)
    #
    # @example Bringing your own migration runner
    #   # Copy lib/bsv/wallet_postgres/migrations/001_create_wallet_tables.rb
    #   # into your own db/migrate directory, then run your framework's
    #   # migrator as normal. `migrate!` is a convenience — not a requirement.
    #
    # === Design notes
    #
    # * JSONB is the source of truth. Every row stores the full record
    #   hash in a +data+ jsonb column; dedicated indexed columns
    #   (+basket+, +tags+, +labels+, +certifier+, ...) exist only to make
    #   queries fast. Reads return the jsonb blob so adding fields to
    #   bsv-wallet's record hashes does not require a schema change.
    #
    # * Outputs upsert on +outpoint+ (unique); certificates upsert on the
    #   composite unique +(type, serial_number, certifier)+. Proofs and
    #   transactions upsert on their +txid+ primary key. Actions are
    #   append-only — the interface has no natural key for actions.
    #
    # * Pagination is ordered by insertion (+id ASC+) to match MemoryStore.
    #
    # * This class is thread-safe because Sequel is — the adapter itself
    #   holds no mutable state beyond the injected database handle.
    class PostgresStore
      include StorageAdapter

      MIGRATIONS_DIR = File.expand_path('migrations', __dir__)

      # Run the shipped wallet schema migrations against +db+.
      #
      # Uses Sequel's migrator so every schema change ships as a numbered
      # migration file and the database tracks which ones have been
      # applied. Safe to call repeatedly.
      #
      # Consumers who prefer their own migration framework can copy the
      # migration file(s) out of +lib/bsv/wallet_postgres/migrations/+
      # instead of calling this helper.
      #
      # @param db [Sequel::Database]
      # @return [void]
      def self.migrate!(db)
        Sequel::Migrator.run(db, MIGRATIONS_DIR)
      end

      # Register the global Sequel query-builder helpers used by this class
      # (+Sequel.pg_array_op+ / +Sequel.pg_jsonb_op+). Unlike the per-database
      # +pg_array+ / +pg_json+ extensions loaded in +initialize+, +pg_array_ops+
      # and +pg_json_ops+ are global — they mutate Sequel's top-level namespace
      # the first time this class body is evaluated (typically on autoload).
      # This is an intentional side effect: any consumer that has
      # +require 'bsv-wallet-postgres'+ in their Gemfile has opted in.
      Sequel.extension :pg_array_ops
      Sequel.extension :pg_json_ops

      # @param db [Sequel::Database] a Sequel database handle. The caller
      #   owns connection lifecycle, pool sizing, and migrations.
      def initialize(db)
        @db = db
        @db.extension :pg_array
        @db.extension :pg_json
      end

      # @return [Sequel::Database] the underlying database handle
      attr_reader :db

      # --- Actions ---

      def store_action(action_data)
        row = action_row(action_data)
        @db[:wallet_actions].insert(row)
        action_data
      end

      def find_actions(query)
        ds = filter_actions(@db[:wallet_actions], query)
        paginate(ds, query).map { |r| symbolise_keys(r[:data]) }
      end

      def count_actions(query)
        filter_actions(@db[:wallet_actions], query).count
      end

      # --- Outputs ---

      def store_output(output_data)
        row = output_row(output_data)
        @db[:wallet_outputs]
          .insert_conflict(
            target: :outpoint,
            update: {
              basket: row[:basket],
              tags: row[:tags],
              spendable: row[:spendable],
              state: row[:state],
              satoshis: row[:satoshis],
              data: row[:data]
            }
          )
          .insert(row)
        output_data
      end

      def find_outputs(query)
        ds = filter_outputs(@db[:wallet_outputs], query)
        paginate(ds, query).map { |r| symbolise_keys(r[:data]) }
      end

      def count_outputs(query)
        filter_outputs(@db[:wallet_outputs], query).count
      end

      def delete_output(outpoint)
        @db[:wallet_outputs].where(outpoint: outpoint).delete.positive?
      end

      # Returns outputs whose effective state is +:spendable+.
      #
      # Legacy rows with +state = NULL+ are treated as spendable when the
      # +spendable+ boolean is true (or absent), matching MemoryStore's
      # effective_state logic.
      #
      # @param basket [String, nil] restrict to this basket when provided
      # @param min_satoshis [Integer, nil] exclude outputs below this value
      # @param sort_order [Symbol] +:asc+ or +:desc+ (default +:desc+, largest first)
      # @return [Array<Hash>]
      def find_spendable_outputs(basket: nil, min_satoshis: nil, sort_order: :desc)
        ds = @db[:wallet_outputs]
             .where(Sequel.lit('(state = ? OR (state IS NULL AND spendable = TRUE))', 'spendable'))
        ds = ds.where(basket: basket) if basket
        if min_satoshis
          ds = ds.where(
            Sequel.lit('COALESCE(satoshis, (data->>?)::bigint, 0) >= ?', 'satoshis', min_satoshis)
          )
        end
        satoshis_expr = Sequel.lit('COALESCE(satoshis, (data->>?)::bigint, 0)', 'satoshis')
        ds = ds.order(sort_order == :asc ? Sequel.asc(satoshis_expr) : Sequel.desc(satoshis_expr))
        ds.all.map { |r| symbolise_keys(r[:data]) }
      end

      # Transitions the state of an existing output.
      #
      # When +new_state+ is +:pending+, sets +pending_since+, +pending_reference+,
      # and +no_send+, and merges those values into the JSONB +data+ blob.
      #
      # When transitioning away from +:pending+, clears the pending metadata
      # columns and removes the corresponding keys from the JSONB blob.
      #
      # @param outpoint [String] the outpoint identifier
      # @param new_state [Symbol] +:spendable+, +:pending+, or +:spent+
      # @param pending_reference [String, nil] caller-supplied label for a pending lock
      # @param no_send [Boolean, nil] true if the lock belongs to a no_send transaction
      # @raise [BSV::Wallet::WalletError] if the outpoint is not found
      # @return [Hash] the updated output hash
      def update_output_state(outpoint, new_state, pending_reference: nil, no_send: nil)
        state_str = new_state.to_s

        if new_state == :pending
          updates = {
            state: state_str,
            pending_since: Sequel.lit('NOW()'),
            pending_reference: pending_reference,
            no_send: no_send ? true : false,
            data: Sequel.lit(
              "data || jsonb_build_object('state', ?, 'pending_since', NOW()::text, 'pending_reference', ?, 'no_send', ?)",
              state_str, pending_reference, no_send ? true : false
            )
          }
        else
          updates = {
            state: state_str,
            pending_since: nil,
            pending_reference: nil,
            no_send: false
          }
          # Remove pending keys from JSONB blob, update state
          updates[:data] = Sequel.lit(
            "(data - 'pending_since' - 'pending_reference' - 'no_send') || jsonb_build_object('state', ?)",
            state_str
          )
        end

        ds = @db[:wallet_outputs].where(outpoint: outpoint)
        rows_updated = ds.update(updates)
        raise WalletError, "Output not found: #{outpoint}" if rows_updated.zero?

        row = ds.first
        symbolise_keys(row[:data])
      end

      # Atomically marks a set of outpoints as +:pending+.
      #
      # Uses +UPDATE ... WHERE state = 'spendable' ... RETURNING outpoint+ so that
      # the check-and-set is atomic at the database level. A concurrent caller that
      # wins the race will have already changed the state to 'pending', so the
      # second caller's WHERE clause will not match and will return nothing. No
      # explicit row-level locking is needed — the UPDATE itself takes the lock.
      #
      # Legacy rows with +state = NULL AND spendable = TRUE+ are also eligible.
      #
      # @param outpoints [Array<String>] outpoint identifiers to lock
      # @param reference [String] caller-supplied pending reference
      # @param no_send [Boolean] true if this is a no_send lock
      # @return [Array<String>] outpoints that were actually locked
      def lock_utxos(outpoints, reference:, no_send: false)
        return [] if outpoints.empty?

        rows = @db[:wallet_outputs]
               .where(outpoint: outpoints)
               .where(Sequel.lit('(state = ? OR (state IS NULL AND spendable = TRUE))', 'spendable'))
               .returning(:outpoint)
               .update(
                 state: 'pending',
                 pending_since: Sequel.lit('NOW()'),
                 pending_reference: reference,
                 no_send: no_send ? true : false,
                 data: Sequel.lit(
                   "data || jsonb_build_object('state', 'pending', 'pending_since', NOW()::text, " \
                   "'pending_reference', ?, 'no_send', ?)",
                   reference, no_send ? true : false
                 )
               )

        rows.map { |r| r[:outpoint] }
      end

      # Releases stale pending locks back to +:spendable+.
      #
      # Any output in +:pending+ state whose +pending_since+ is older than
      # +timeout+ seconds is reset to +spendable+ and its pending metadata is
      # cleared. Outputs with +no_send = true+ are exempt and remain pending.
      # Outputs with +pending_since = NULL+ are also skipped — they are treated
      # as freshly locked (NULL means "just acquired but no timestamp yet").
      #
      # @param timeout [Integer] age in seconds before a lock is considered stale (default 300)
      # @return [Integer] number of outputs released
      def release_stale_pending!(timeout: 300)
        rows = @db[:wallet_outputs]
               .where(state: 'pending')
               .where(Sequel.lit('no_send IS NOT TRUE'))
               .where(Sequel.lit('pending_since IS NOT NULL'))
               .where(Sequel.lit('pending_since < (NOW() - INTERVAL ?)', "#{timeout} seconds"))
               .returning(:outpoint)
               .update(
                 state: 'spendable',
                 pending_since: nil,
                 pending_reference: nil,
                 no_send: false,
                 data: Sequel.lit(
                   "(data - 'pending_since' - 'pending_reference' - 'no_send') || jsonb_build_object('state', 'spendable')"
                 )
               )

        rows.length
      end

      # --- Certificates ---

      def store_certificate(cert_data)
        row = certificate_row(cert_data)
        @db[:wallet_certificates]
          .insert_conflict(
            target: %i[type serial_number certifier],
            update: { subject: row[:subject], data: row[:data] }
          )
          .insert(row)
        cert_data
      end

      def find_certificates(query)
        ds = filter_certificates(@db[:wallet_certificates], query)
        paginate(ds, query).map { |r| symbolise_keys(r[:data]) }
      end

      def count_certificates(query)
        filter_certificates(@db[:wallet_certificates], query).count
      end

      def delete_certificate(type:, serial_number:, certifier:)
        @db[:wallet_certificates]
          .where(type: type, serial_number: serial_number, certifier: certifier)
          .delete
          .positive?
      end

      # --- Proofs ---

      def store_proof(txid, bump_hex)
        @db[:wallet_proofs]
          .insert_conflict(target: :txid, update: { bump_hex: bump_hex })
          .insert(txid: txid, bump_hex: bump_hex)
      end

      def find_proof(txid)
        @db[:wallet_proofs].where(txid: txid).get(:bump_hex)
      end

      # --- Transactions ---

      def store_transaction(txid, tx_hex)
        @db[:wallet_transactions]
          .insert_conflict(target: :txid, update: { tx_hex: tx_hex })
          .insert(txid: txid, tx_hex: tx_hex)
      end

      def find_transaction(txid)
        @db[:wallet_transactions].where(txid: txid).get(:tx_hex)
      end

      # --- Settings ---

      def store_setting(key, value)
        @db[:wallet_settings]
          .insert_conflict(target: :key, update: { value: value })
          .insert(key: key, value: value)
      end

      def find_setting(key)
        @db[:wallet_settings].where(key: key).get(:value)
      end

      private

      # --- Row builders ---

      def action_row(data)
        {
          txid: data[:txid],
          labels: Sequel.pg_array(Array(data[:labels]), :text),
          data: Sequel.pg_jsonb(data.to_h)
        }
      end

      def output_row(data)
        spendable = data[:spendable] != false # nil treated as spendable, like MemoryStore
        state = data[:state]&.to_s
        {
          outpoint: data[:outpoint],
          basket: data[:basket],
          tags: Sequel.pg_array(Array(data[:tags]), :text),
          spendable: spendable,
          state: state,
          satoshis: data[:satoshis],
          data: Sequel.pg_jsonb(data.to_h)
        }
      end

      def certificate_row(data)
        {
          type: data[:type],
          serial_number: data[:serial_number],
          certifier: data[:certifier],
          subject: data[:subject],
          data: Sequel.pg_jsonb(data.to_h)
        }
      end

      # --- Filters ---

      def filter_actions(ds, query)
        apply_array_filter(ds, :labels, query[:labels], query[:label_query_mode])
      end

      def filter_outputs(ds, query)
        ds = ds.where(outpoint: query[:outpoint]) if query[:outpoint]
        ds = ds.where(basket: query[:basket]) if query[:basket]
        ds = apply_array_filter(ds, :tags, query[:tags], query[:tag_query_mode])
        ds = ds.where(spendable: true) unless query[:include_spent]
        ds
      end

      def filter_certificates(ds, query)
        ds = ds.where(certifier: query[:certifiers]) if query[:certifiers]
        ds = ds.where(type: query[:types]) if query[:types]
        ds = ds.where(subject: query[:subject]) if query[:subject]
        ds = apply_attributes_filter(ds, query[:attributes]) if query[:attributes]
        ds
      end

      def apply_array_filter(ds, column, values, mode)
        return ds unless values

        array = Sequel.pg_array(Array(values), :text)
        op    = Sequel.pg_array_op(column)
        if mode == 'all'
          ds.where(op.contains(array))
        else
          ds.where(op.overlaps(array))
        end
      end

      def apply_attributes_filter(ds, attrs)
        # Match certificates whose stored fields hash contains every
        # key/value pair in +attrs+. Symbol keys stringify when the
        # record is serialised to JSONB, so symbol/string keys both work.
        fragment = attrs.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
        ds.where(Sequel.lit('data->\'fields\' @> ?::jsonb', fragment.to_json))
      end

      # --- Pagination ---

      def paginate(ds, query)
        ds.order(:id)
          .offset(query[:offset] || 0)
          .limit(query[:limit] || 10)
          .all
      end

      # --- JSONB read helpers ---

      # Recursively convert string-keyed hashes to symbol-keyed hashes so
      # reads round-trip with MemoryStore's contract. pg_json returns
      # string keys by default wrapped in +Sequel::Postgres::JSONBHash+
      # / +JSONBArray+, which are +DelegateClass+-based — not Hash/Array
      # subclasses — so the case statement uses +to_hash+ / +to_ary+
      # coercion to handle them.
      def symbolise_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = symbolise_keys(v) }
        when Array
          obj.map { |e| symbolise_keys(e) }
        else
          return symbolise_keys(obj.to_hash) if obj.respond_to?(:to_hash)
          return symbolise_keys(obj.to_ary)  if obj.respond_to?(:to_ary)

          obj
        end
      end
    end
  end
end
