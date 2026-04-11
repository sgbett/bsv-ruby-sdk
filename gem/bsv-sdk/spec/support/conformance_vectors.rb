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
end
