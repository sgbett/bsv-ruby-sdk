# frozen_string_literal: true

require 'json'

# Loader for cross-SDK conformance test vectors.
#
# Vectors live in `spec/conformance/vectors/` and are vendored verbatim from
# the BSV reference SDKs (Go, TypeScript). Provenance (source SDK, path, and
# commit SHA) is recorded in `spec/conformance/vectors/README.md`.
#
# Keep this loader minimal — each spec family knows its own vector shape.
# Do not grow a single generic parser here; add parsing logic per spec.
#
# See: `docs/testing/conformance-vectors.md` and HLR sgbett/bsv-ruby-sdk#307.
module ConformanceVectors
  VECTORS_DIR = File.expand_path('../conformance/vectors', __dir__)

  # Root of the canonical corpus cache populated by bin/conformance/sync.
  CANONICAL_DIR = File.expand_path('../../../../tmp/conformance-vectors/conformance/vectors', __dir__)
  CANONICAL_REGRESSIONS_DIR = File.expand_path('../../../../tmp/conformance-vectors/conformance/vectors/regressions', __dir__)

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

  # Load a canonical corpus envelope by dot-separated ID or relative path.
  # Resolves dots to directory separators: "sdk.keys.key-derivation" →
  # "sdk/keys/key-derivation.json". Hyphens within a segment are preserved.
  #
  # @param id_or_path [String] dot-separated vector ID or path relative to canonical vectors dir
  # @return [Hash] parsed JSON envelope
  def self.canonical(id_or_path)
    assert_canonical_cache!
    path = File.join(CANONICAL_DIR, "#{id_or_path.tr('.', '/')}.json")
    raise "Canonical vector not found: #{path}" unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  # Yields each vector entry from a canonical corpus envelope.
  # Skips entries with skip: true and logs the skip reason.
  #
  # @param vector_id [String] dot-separated vector ID
  # @yieldparam envelope [Hash] the full parsed envelope
  # @yieldparam vector [Hash] individual vector entry
  def self.each_canonical_vector(vector_id, &block)
    envelope = canonical(vector_id)
    envelope.fetch('vectors', []).each do |vector|
      if vector['skip']
        warn "[conformance] skipping #{vector['id']}: #{vector['skip_reason']}"
        next
      end
      block.call(envelope, vector)
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
