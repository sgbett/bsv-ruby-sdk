# frozen_string_literal: true

require 'json'
require 'support/conformance_vectors'

# Shared loader for the canonical sdk.scripts.evaluation corpus.
#
# The evaluation file is large (5117 vectors). This module loads it once per
# process (memoised) and provides tag-based filtering so individual specs never
# iterate the full set unfiltered.
#
# Usage:
#
#   EvaluationCorpus.each(tags: %w[sighash]) { |envelope, vector| ... }
#   EvaluationCorpus.each(tags: %w[sighash forkid]) { |envelope, vector| ... }
#
# Vectors with `skip: true` are silently skipped (skip_reason is warned).
#
# Reuse: Task #846 (script evaluation spec) imports this helper directly.
# The filter API is intentionally small — add new keyword args rather than
# positional parameters if more filtering modes are needed.

module EvaluationCorpus
  CORPUS_ID = 'sdk.scripts.evaluation'

  # Yield each vector entry from the evaluation corpus that matches all of
  # the given tag filters.
  #
  # @param tags [Array<String>] required tags (vector must include ALL of them)
  # @yieldparam envelope [Hash] the top-level corpus envelope
  # @yieldparam vector [Hash] individual vector entry
  def self.each(tags: [], &block)
    envelope.fetch('vectors', []).each do |vector|
      next if vector['skip']
      next unless tags.empty? || tags.all? { |t| vector['tags']&.include?(t) }

      block.call(envelope, vector)
    end
  end

  # Return the count of vectors matching the given tag filter (for spec
  # descriptions and pending-failure tracking).
  #
  # @param tags [Array<String>]
  # @return [Integer]
  def self.count(tags: [])
    result = 0
    each(tags: tags) { result += 1 }
    result
  end

  # The raw parsed envelope (memoised for the process lifetime).
  #
  # @return [Hash]
  def self.envelope
    @envelope ||= ConformanceVectors.canonical(CORPUS_ID)
  end
end
