#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot migration script: splits the monorepo CHANGELOG.md into per-gem
# changelog files and replaces the original with a brief index.
#
# Usage:
#   ruby script/split_changelog.rb
#
# Produces:
#   CHANGELOG-sdk.md
#   CHANGELOG-wallet.md
#   CHANGELOG-wallet-postgres.md
#   CHANGELOG-attest.md
#   CHANGELOG.md  (overwritten with index)

GEM_SLUGS = %w[sdk wallet wallet-postgres attest].freeze

# Map from slug used in headers/tags to the gem name used in output
GEM_NAMES = {
  'sdk' => 'bsv-sdk',
  'wallet' => 'bsv-wallet',
  'wallet-postgres' => 'bsv-wallet-postgres',
  'attest' => 'bsv-attest'
}.freeze

# --- Parsing helpers ---

# Parse a section header like "## sdk-0.8.2 / wallet-0.3.4 — 2026-04-08"
# or "## Unreleased — sdk-0.9.0" into a hash of { slug => version_or_label }
# plus the date string.
def parse_header(line)
  # Strip "## " prefix
  rest = line.sub(/^## /, '').strip
  # Split off date after " — " or " -- "
  parts = rest.split(/\s+[—–-]{1,2}\s+/, 2)

  gem_part = parts[0]
  date = parts[1] # may be nil for "## Unreleased — sdk-0.9.0" style

  gems = {}

  if gem_part.start_with?('Unreleased')
    # "Unreleased — sdk-0.9.0" → sdk => 'Unreleased'
    # The date field actually has the gem-version
    if date
      date.scan(/([\w-]+)-([\d.]+)/) do |slug, ver|
        gems[slug] = 'Unreleased'
      end
    end
    date = nil
  else
    # "sdk-0.8.2 / wallet-0.3.4" or "wallet-postgres-0.1.0"
    gem_part.split(%r{\s*/\s*}).each do |chunk|
      # Match "wallet-postgres-0.1.0" or "sdk-0.8.2"
      # Greedy slug: everything up to the last -\d+.\d+.\d+
      if chunk.match(/\A(.+)-(\d+\.\d+\.\d+)\z/)
        gems[$1] = $2
      end
    end
  end

  { gems: gems, date: date }
end

# Determine which gem(s) a bullet line targets based on its [tag] prefix.
# Returns an array of slugs and the line with the prefix stripped.
def parse_bullet_tag(line)
  if line.match(/\A- \[([^\]]+)\]\s*(.*)/)
    tags_str = $1
    rest = $2
    tags = tags_str.split(/,\s*/).map(&:strip)
    [tags, "- #{rest}"]
  else
    [nil, line]
  end
end

# --- Main ---

source = File.read('CHANGELOG.md')
lines = source.lines.map(&:chomp)

# Find the first ## line (skip preamble)
first_section = lines.index { |l| l.start_with?('## ') }
abort 'No ## section found in CHANGELOG.md' unless first_section

# Parse into sections: each section is { header_info:, raw_header:, body: [] }
sections = []
current = nil

lines[first_section..].each do |line|
  if line.start_with?('## ')
    current = { header_info: parse_header(line), raw_header: line, body: [] }
    sections << current
  else
    current[:body] << line if current
  end
end

# --- Route content to per-gem buckets ---

# Structure: { slug => [ { version:, date:, subsections: { name => [lines] } } ] }
gem_versions = GEM_SLUGS.each_with_object({}) { |s, h| h[s] = {} }

# Ensure every gem has an Unreleased bucket
GEM_SLUGS.each { |s| gem_versions[s]['Unreleased'] = { date: nil, subsections: {} } }

sections.each do |section|
  header = section[:header_info]
  section_gems = header[:gems] # { slug => version }
  date = header[:date]

  # Initialise version buckets for gems named in this header
  section_gems.each do |slug, version|
    gem_versions[slug][version] ||= { date: date, subsections: {} }
  end

  current_subsection = '_prose' # content before the first ### goes here
  # Track which bullet targets what, for continuation lines
  last_targets = nil

  section[:body].each do |line|
    if line.start_with?('### ')
      current_subsection = line
      last_targets = nil
      next
    end

    if line.start_with?('- ')
      tags, stripped = parse_bullet_tag(line)

      if tags
        # Explicitly tagged bullet
        targets = tags
        output_line = stripped
      else
        # Untagged bullet — falls back to section gems
        targets = section_gems.keys
        output_line = line
      end

      last_targets = targets

      targets.each do |slug|
        next unless gem_versions.key?(slug)

        version = section_gems[slug] || 'Unreleased'
        gem_versions[slug][version] ||= { date: date, subsections: {} }
        bucket = gem_versions[slug][version][:subsections]
        bucket[current_subsection] ||= []
        bucket[current_subsection] << output_line
      end

    elsif line.start_with?('  ') && last_targets
      # Continuation line of previous bullet
      last_targets.each do |slug|
        next unless gem_versions.key?(slug)

        version = section_gems[slug] || 'Unreleased'
        bucket = gem_versions[slug][version][:subsections]
        bucket[current_subsection] ||= []
        bucket[current_subsection] << line
      end

    elsif line.strip.empty?
      # Blank line — append to all gems in this section for spacing
      # (only if they already have content in this subsection)
      section_gems.each_key do |slug|
        version = section_gems[slug]
        bucket = gem_versions[slug][version][:subsections]
        bucket[current_subsection] << '' if bucket[current_subsection]&.any?
      end

    else
      # Prose line — goes to all gems in this section
      section_gems.each_key do |slug|
        version = section_gems[slug]
        bucket = gem_versions[slug][version][:subsections]
        bucket[current_subsection] ||= []
        bucket[current_subsection] << line
      end
    end
  end
end

# --- Generate output files ---

def write_gem_changelog(slug, versions)
  gem_name = GEM_NAMES[slug]
  out = []
  out << "# Changelog \u2014 #{gem_name}"
  out << ''
  out << "All notable changes to the `#{gem_name}` gem are documented here."
  out << ''
  out << 'The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)'
  out << 'and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).'
  out << ''

  # Sort versions: Unreleased first, then by version descending
  sorted = versions.keys.sort_by do |v|
    if v == 'Unreleased'
      [0, '']
    else
      parts = v.split('.').map(&:to_i)
      [1, parts.map { |p| -p }]
    end
  end

  sorted.each do |version|
    data = versions[version]
    subsections = data[:subsections]

    # Skip empty versions (no content at all)
    has_content = subsections.values.any? { |lines| lines.any? { |l| !l.strip.empty? } }
    next unless has_content

    # Section header
    if version == 'Unreleased'
      out << '## Unreleased'
    elsif data[:date]
      out << "## #{version} \u2014 #{data[:date]}"
    else
      out << "## #{version}"
    end
    out << ''

    # Prose (content before first ###)
    if subsections['_prose']&.any? { |l| !l.strip.empty? }
      subsections['_prose'].each { |l| out << l }
      # Ensure trailing blank line after prose
      out << '' unless out.last.strip.empty?
    end

    # Named subsections
    subsections.each do |name, content|
      next if name == '_prose'
      next unless content.any? { |l| !l.strip.empty? }

      out << name
      out << ''
      content.each { |l| out << l }
      out << '' unless out.last.strip.empty?
    end
  end

  # Trim trailing blank lines
  out.pop while out.last&.strip&.empty?
  out << ''

  filename = "CHANGELOG-#{slug}.md"
  File.write(filename, out.join("\n"))
  puts "  wrote #{filename} (#{out.length} lines)"
end

# Add a minimal attest entry if it has no content
attest = gem_versions['attest']
if attest.values.all? { |v| v[:subsections].values.flatten.all? { |l| l.strip.empty? } }
  attest['0.1.0'] = {
    date: nil,
    subsections: { '_prose' => ['Initial release of `bsv-attest`.'] }
  }
end

puts 'Generating per-gem changelogs...'
GEM_SLUGS.each { |slug| write_gem_changelog(slug, gem_versions[slug]) }

# --- Write index ---

index = <<~INDEX
  # Changelog

  This repository ships four gems with independent versioning and changelogs:

  | Gem | Changelog |
  |-----|-----------|
  | `bsv-sdk` | [CHANGELOG-sdk.md](CHANGELOG-sdk.md) |
  | `bsv-wallet` | [CHANGELOG-wallet.md](CHANGELOG-wallet.md) |
  | `bsv-wallet-postgres` | [CHANGELOG-wallet-postgres.md](CHANGELOG-wallet-postgres.md) |
  | `bsv-attest` | [CHANGELOG-attest.md](CHANGELOG-attest.md) |

  Each changelog follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
  format. Each gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
  independently.
INDEX

File.write('CHANGELOG.md', index)
puts '  wrote CHANGELOG.md (index)'

# --- Verification ---

total_bullets = 0
GEM_SLUGS.each do |slug|
  filename = "CHANGELOG-#{slug}.md"
  content = File.read(filename)
  bullets = content.lines.count { |l| l.start_with?('- ') }
  total_bullets += bullets
  puts "  #{filename}: #{bullets} bullets"
end
puts "  total bullets across all gems: #{total_bullets}"

original_bullets = source.lines.count { |l| l.start_with?('- ') && !l.match?(/\A- \*\*`bsv-/) && !l.match?(/\A- `## /) }
puts "  original CHANGELOG.md bullets (excl. preamble): #{original_bullets}"
# Note: dual-tag bullets are duplicated, so total >= original is expected
puts '  (dual-tag bullets are duplicated across gems, so total >= original)'
