# frozen_string_literal: true

# Tx cache specs have been reorganised into focused files (Phase E, #887):
#
#   tx_cache_lifecycle_spec.rb     — owning-Tx backref, #initialize_copy, invalidator stubs
#   tx_cache_memoisation_spec.rb   — structural regression (O(N+M) sha256d call count)
#   tx_cache_invalidation_spec.rb  — §3 contract table, one describe per row, shared examples
#
# This file is retained as a breadcrumb to avoid confusing git blame / test runner history.
