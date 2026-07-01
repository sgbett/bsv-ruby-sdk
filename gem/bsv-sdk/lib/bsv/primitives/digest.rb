# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    # Cryptographic hash functions and HMAC operations.
    #
    # Thin wrappers around +OpenSSL::Digest+ and +OpenSSL::HMAC+ providing
    # the hash algorithms used throughout the BSV protocol: SHA-1, SHA-256,
    # double-SHA-256, SHA-512, RIPEMD-160, Hash160, HMAC, and PBKDF2.
    #
    # @note **Per-thread cached OpenSSL contexts**
    #
    #   +sha256+, +sha256d+, +sha1+, and +sha512+ each cache one
    #   +OpenSSL::Digest+ instance per thread in +Thread.current+ under a
    #   namespaced key (e.g. +:bsv_sdk_sha256_digest+).  On every call the
    #   context is reset with +OpenSSL::Digest#reset+, which calls
    #   +EVP_DigestInit_ex+ against the +EVP_MD*+ already stored on the
    #   context.  This skips the +EVP_get_digestbyname+ namemap lookup that
    #   +OpenSSL::Digest::SHA256.new+ (or +.digest+) performs on every fresh
    #   allocation.  The namemap cost is paid exactly once per thread per
    #   algorithm.
    #
    #   **Fibre-local semantics.**  +Thread.current[:key]+ is *fibre-local*
    #   in MRI (documented since Ruby 2.0, verified on 3.3 / 3.4 / 4.0) — each
    #   Fibre gets its own cached context.  This is stronger than the SDK
    #   currently requires (no Fibres in +lib/+) and is correctly safe if
    #   Fibres are introduced later.  The HLR body's "GVL makes it safe"
    #   rationale is subtly wrong; the correct reason is fibre-local scope.
    #
    #   **Do not touch the cached instances externally.**  The keys
    #   +:bsv_sdk_sha256_digest+, +:bsv_sdk_sha1_digest+, and
    #   +:bsv_sdk_sha512_digest+ are technically reachable via +Thread.current+
    #   but must never have +update+ called on them outside this module.
    #   Calling +update+ out-of-band would corrupt the next call's input.
    #
    #   **User-visible invariants are unchanged:** return values are always
    #   +ASCII-8BIT+ binary strings; identical inputs always produce identical
    #   outputs; successive calls return distinct +String+ objects (output
    #   buffers are never cached).
    #
    #   **Prefix convention.**  +:bsv_sdk_<algo>_digest+ is the SDK-wide
    #   naming convention for any future +Thread.current+ usage in this
    #   codebase — the prefix avoids collision with other libraries that may
    #   also use +Thread.current+.
    #
    #   **FIPS.**  SHA-1, SHA-256, and SHA-512 remain FIPS-approved algorithms
    #   under this pattern; the algorithm fetch happens once at +.new+, not per
    #   call.
    #
    #   **CI matrix.**  Verified on MRI 3.3, 3.4, and 4.0.  JRuby and
    #   TruffleRuby are not in the CI matrix — per-thread caching is correct on
    #   true-parallel Rubies (each thread has independent +Thread.current+) but
    #   unverified here.
    #
    #   **Why other SDKs do not do this.**  The TypeScript, Go, and Python SDKs
    #   allocate fresh digest contexts per call because their OpenSSL bindings
    #   cache the algorithm handle internally.  MRI's +openssl+ gem bridges
    #   through +EVP_get_digestbyname+ on every allocation — we are patching
    #   the Ruby binding overhead, not diverging from BSV protocol semantics.
    #
    #   **Out of scope with rationale:**
    #   - +ripemd160+ — pure-Ruby implementation; no OpenSSL context.
    #   - +hmac_sha256+ / +hmac_sha512+ — HMAC key changes per call.  A future
    #     cache *must* key on wrapper-object identity (+object_id+), never on
    #     key bytes — a key-bytes cache lookup would create a secret-dependent
    #     side-channel via cache-hit timing.
    #   - +pbkdf2_hmac_sha512+ — one-shot at BIP-39 seed derivation; not a
    #     hot path.
    module Digest
      module_function

      # Compute SHA-1 digest.
      #
      # @param data [String] binary data to hash
      # @return [String] 20-byte digest (ASCII-8BIT)
      def sha1(data)
        d = Thread.current[:bsv_sdk_sha1_digest] ||= OpenSSL::Digest.new('SHA1')
        d.reset
        d.update(data)
        d.digest
      end

      # Compute SHA-256 digest.
      #
      # @param data [String] binary data to hash
      # @return [String] 32-byte digest (ASCII-8BIT)
      def sha256(data)
        d = Thread.current[:bsv_sdk_sha256_digest] ||= OpenSSL::Digest.new('SHA256')
        d.reset
        d.update(data)
        d.digest
      end

      # Compute double-SHA-256 (SHA-256d) digest.
      #
      # Used extensively in Bitcoin for transaction and block hashing.
      # Inlines the two-round chain against the same cached SHA-256 context,
      # saving one context allocation, one namemap lookup, one intermediate
      # +String+, and one +module_function+ dispatch per call compared with
      # the naive +sha256(sha256(data))+ decomposition.
      #
      # @param data [String] binary data to hash
      # @return [String] 32-byte digest (ASCII-8BIT)
      def sha256d(data)
        d = Thread.current[:bsv_sdk_sha256_digest] ||= OpenSSL::Digest.new('SHA256')
        d.reset
        d.update(data)
        first = d.digest
        d.reset # defensive: some Ruby versions internally reset after #digest
        d.update(first)
        d.digest
      end

      alias hash256 sha256d
      module_function :hash256

      # Compute SHA-512 digest.
      #
      # @param data [String] binary data to hash
      # @return [String] 64-byte digest (ASCII-8BIT)
      def sha512(data)
        d = Thread.current[:bsv_sdk_sha512_digest] ||= OpenSSL::Digest.new('SHA512')
        d.reset
        d.update(data)
        d.digest
      end

      # Compute RIPEMD-160 digest.
      #
      # @note Uses the pure-Ruby {BSV::Primitives::Ripemd160} implementation —
      #   no OpenSSL context is held or cached here.  RIPEMD-160 is not in
      #   scope for the per-thread caching optimisation (different optimisation
      #   track; not currently a hot path).
      #
      # @param data [String] binary data to hash
      # @return [String] 20-byte digest (ASCII-8BIT)
      def ripemd160(data)
        Ripemd160.digest(data)
      end

      # Compute Hash160: RIPEMD-160(SHA-256(data)).
      #
      # Standard Bitcoin hash used for addresses and P2PKH script matching.
      #
      # @param data [String] binary data to hash
      # @return [String] 20-byte digest (ASCII-8BIT)
      def hash160(data)
        ripemd160(sha256(data))
      end

      # Compute HMAC-SHA-256.
      #
      # @note HMAC context reuse is deferred — the key changes per call, so a
      #   future cache must key on wrapper-object identity (+object_id+), never
      #   on key bytes, to avoid a secret-dependent side-channel via cache-hit
      #   timing.
      #
      # @param key [String] HMAC key
      # @param data [String] data to authenticate
      # @return [String] 32-byte MAC (ASCII-8BIT)
      def hmac_sha256(key, data)
        OpenSSL::HMAC.digest('SHA256', key, data)
      end

      # Compute HMAC-SHA-512.
      #
      # @note HMAC context reuse is deferred — see +hmac_sha256+ note.
      #
      # @param key [String] HMAC key
      # @param data [String] data to authenticate
      # @return [String] 64-byte MAC (ASCII-8BIT)
      def hmac_sha512(key, data)
        OpenSSL::HMAC.digest('SHA512', key, data)
      end

      # Derive a key using PBKDF2-HMAC-SHA-512.
      #
      # Used by BIP-39 to convert mnemonic phrases into seeds.
      # One-shot at key creation — not a hot path; no context reuse applied.
      #
      # @param password [String] the password (mnemonic phrase)
      # @param salt [String] the salt (+"mnemonic"+ + passphrase)
      # @param iterations [Integer] iteration count (default: 2048 per BIP-39)
      # @param key_length [Integer] desired output length in bytes (default: 64)
      # @return [String] derived key bytes (ASCII-8BIT)
      def pbkdf2_hmac_sha512(password, salt, iterations: 2048, key_length: 64)
        OpenSSL::PKCS5.pbkdf2_hmac(password, salt, iterations, key_length, 'sha512')
      end
    end
  end
end
