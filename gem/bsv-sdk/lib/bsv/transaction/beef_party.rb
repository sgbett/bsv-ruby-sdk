# frozen_string_literal: true

module BSV
  module Transaction
    # Transaction::Beef subclass that tracks per-party knowledge of wtxids.
    #
    # Used in multi-party BEEF exchange to avoid re-transmitting transaction
    # data and proofs that a counterparty already possesses. Each party is
    # identified by a caller-supplied string and associated with the set of
    # wtxids it is known to hold.
    #
    # @example Two-party exchange
    #   party = BSV::Transaction::BeefParty.new(['alice', 'bob'])
    #   party.merge_beef_from_party('alice', alice_beef)
    #   trimmed = party.trimmed_beef_for_party('bob')  # plain Transaction::Beef
    class BeefParty < Beef
      # @param initial_parties [Array<String>] optional initial party identifiers
      # @raise [ArgumentError] if +initial_parties+ contains duplicates
      #
      # Defaults to BEEF_V2 (BRC-96) because TXID-only entries — which are
      # central to BeefParty's purpose — are only valid in V2. Matches the TS
      # SDK's +new Beef()+ default.
      def initialize(initial_parties = [])
        super(version: BEEF_V2)
        @party_knowledge = {}
        initial_parties.each { |p| add_party(p) }
      end

      # @param party_id [String]
      # @return [Boolean] true if +party_id+ has been added
      def party?(party_id)
        @party_knowledge.key?(party_id)
      end

      # Add a new unique party identifier.
      #
      # @param party_id [String]
      # @raise [ArgumentError] if +party_id+ is already known
      def add_party(party_id)
        raise ArgumentError, "duplicate party #{party_id}" if party?(party_id)

        @party_knowledge[party_id] = Set.new
      end

      # Record additional wtxids as known to +party_id+.
      #
      # Auto-creates the party if it is not yet known (TS parity). Also
      # merges a TXID-only entry into the underlying bundle for each wtxid.
      #
      # @param party_id [String] party identifier (auto-created if unknown)
      # @param wtxids [Array<String>] 32-byte wire-order binary wtxids
      # @raise [ArgumentError] if any element of +wtxids+ is not a valid wtxid
      def add_known_wtxids_for_party(party_id, wtxids)
        add_party(party_id) unless party?(party_id)
        wtxids.each do |wtxid|
          BSV::Primitives::Hex.validate_wtxid!(wtxid, name: 'wtxid')
          @party_knowledge[party_id].add(wtxid)
          merge_txid_only(wtxid)
        end
      end

      # @param party_id [String]
      # @return [Array<String>] 32-byte wire-order binary wtxids known to +party_id+
      # @raise [ArgumentError] if +party_id+ is unknown
      def known_wtxids_for_party(party_id)
        raise ArgumentError, "unknown party #{party_id}" unless party?(party_id)

        @party_knowledge[party_id].to_a
      end

      # Merge a Transaction::Beef received from +party_id+.
      #
      # Merges all transactions and BUMPs from +beef_or_binary+ into +self+,
      # then records the valid wtxids of the merged bundle as known to
      # +party_id+. Auto-creates the party if not yet known.
      #
      # @param party_id [String] party identifier
      # @param beef_or_binary [Transaction::Beef, String] a Transaction::Beef
      #   instance or raw binary BEEF bytes
      def merge_beef_from_party(party_id, beef_or_binary)
        beef = beef_or_binary.is_a?(Beef) ? beef_or_binary : Beef.from_binary(beef_or_binary)
        # Capture the set of wtxids the party actually sent before merging.
        beef_wtxids = beef.transactions.map(&:wtxid)
        merge(beef)
        # Record knowledge of any tx the party sent that is now provably valid
        # against the merged state. This captures the cross-bundle case where
        # an unproven tx in +beef+ becomes valid via inputs already proven in
        # +self+ (and conversely doesn't record knowledge the party never sent).
        known = valid_wtxids & beef_wtxids
        add_known_wtxids_for_party(party_id, known)
      end

      # Return a new Transaction::Beef (not Transaction::BeefParty) with
      # TXID-only entries that are known to +party_id+ removed.
      #
      # RAW_TX and RAW_TX_AND_BUMP entries are always retained even when the
      # party knows the txid — those formats carry proof data. BUMP indices
      # are renumbered if any unreferenced bumps are dropped.
      #
      # Does not mutate +self+.
      #
      # @param party_id [String]
      # @return [Transaction::Beef] a new trimmed bundle (plain Beef, not BeefParty)
      # @raise [ArgumentError] if +party_id+ is unknown
      def trimmed_beef_for_party(party_id)
        raise ArgumentError, "unknown party #{party_id}" unless party?(party_id)

        known = @party_knowledge[party_id].to_a

        # Build a plain Beef from our current state so trim_known_wtxids
        # returns a Beef, not a BeefParty.
        plain = Beef.new(version: @version, bumps: @bumps.dup, transactions: @transactions.dup)
        plain.instance_variable_set(:@subject_wtxid, @subject_wtxid)
        plain.instance_variable_set(:@txs_not_valid, @txs_not_valid&.dup)
        plain.trim_known_wtxids(known)
      end
    end
  end
end
