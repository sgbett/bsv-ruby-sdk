# frozen_string_literal: true

require 'json'

# Loader for cross-SDK conformance test vectors.
#
# Primary source: the canonical ts-stack conformance corpus, fetched into
# `tmp/conformance-vectors/` by `bin/conformance/sync` at the SHA pinned in
# `.architecture/conformance.lock`. Use `canonical` / `each_canonical_vector`
# / `canonical_regression` to read from it.
#
# Secondary source: a small set of Ruby-local fixtures kept under
# `spec/conformance/vectors/` because no canonical upstream equivalent exists
# (see that directory's README for the surviving entries and the rationale).
# Use `load` / `load_rows` to read those.
#
# Keep this loader minimal — each spec family knows its own vector shape.
# Do not grow a single generic parser here; add parsing logic per spec.
#
# See: `docs/testing/conformance-vectors.md` and HLR sgbett/bsv-ruby-sdk#837.
module ConformanceVectors
  REPO_ROOT     = File.expand_path('../../../..', __dir__)
  VECTORS_DIR   = File.expand_path('../conformance/vectors', __dir__)
  CANONICAL_DIR = File.join(REPO_ROOT, 'tmp', 'conformance-vectors', 'conformance', 'vectors')
  CANONICAL_REGRESSIONS_DIR = File.join(CANONICAL_DIR, 'regressions')

  # Read a vector file and return its parsed JSON content.
  #
  # @param filename [String] file name relative to `spec/conformance/vectors/`
  # @return [Object] parsed JSON (typically Array or Hash)
  def self.load(filename)
    path = File.join(VECTORS_DIR, filename)
    raise "Conformance vector not found: #{path}" unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  # Bitcoin Core-style test files (sighash_*.json, script_tests.json) are
  # arrays whose first rows are single-element metadata/comment arrays. This
  # helper returns only the test rows.
  #
  # @param filename [String]
  # @return [Array<Array>] test rows only, with metadata/comment rows dropped
  def self.load_rows(filename)
    load(filename).reject { |row| row.is_a?(Array) && row.length == 1 }
  end

  # Load a canonical corpus envelope by its dot-separated vector ID.
  # Resolves dots to directory separators: "sdk.keys.key-derivation" →
  # "sdk/keys/key-derivation.json". Hyphens within a segment are preserved.
  # Pass the ID only — never a path or a name with a .json suffix.
  #
  # @param vector_id [String] dot-separated vector ID (no slashes, no extension)
  # @return [Hash] parsed JSON envelope
  def self.canonical(vector_id)
    assert_canonical_cache!
    path = File.join(CANONICAL_DIR, "#{vector_id.tr('.', '/')}.json")
    raise "Canonical vector not found: #{path}" unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  # Yields each vector entry from a canonical corpus envelope.
  # Skips entries with skip: true and logs the skip reason.
  #
  # @param vector_id [String] dot-separated vector ID
  # @yieldparam envelope [Hash] the full parsed envelope
  # @yieldparam vector [Hash] individual vector entry
  def self.each_canonical_vector(vector_id)
    envelope = canonical(vector_id)
    envelope.fetch('vectors', []).each do |vector|
      if vector['skip']
        warn "[conformance] skipping #{vector['id']}: #{vector['skip_reason']}"
        next
      end
      yield envelope, vector
    end
  end

  # Load a regression envelope by name from the regressions/ directory.
  #
  # @param name [String] regression file name without .json extension
  # @return [Hash] parsed JSON envelope
  def self.canonical_regression(name)
    assert_canonical_cache!
    path = File.join(CANONICAL_REGRESSIONS_DIR, "#{name}.json")
    raise "Canonical regression not found: #{path}" unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  def self.assert_canonical_cache!
    return if Dir.exist?(CANONICAL_DIR) && !Dir.empty?(CANONICAL_DIR)

    raise 'Canonical conformance cache is empty or missing. ' \
          "Run bin/conformance/sync first; expected #{CANONICAL_DIR}"
  end
  private_class_method :assert_canonical_cache!
end
