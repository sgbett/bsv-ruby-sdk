# frozen_string_literal: true

# Gem releases are handled by the /release Claude Code skill.
# See CLAUDE.md for the release workflow and tag conventions.
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

def generate_reference_index(output_dir) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength
  require 'csv'
  csv_path = File.join(output_dir, 'index.csv')
  return unless File.exist?(csv_path)

  modules = []
  classes = []
  CSV.foreach(csv_path, headers: true) do |row|
    next unless %w[Module Class].include?(row['type'])

    entry = { name: row['name'], path: row['path'] }
    row['type'] == 'Module' ? modules << entry : classes << entry
  end

  File.open(File.join(output_dir, 'index.md'), 'w') do |f|
    f.puts '# API Reference'
    f.puts
    f.puts 'Auto-generated from source using [YARD](https://yardoc.org/).'
    f.puts
    f.puts '## Modules'
    f.puts
    modules.sort_by { |e| e[:name] }.each { |e| f.puts "- [#{e[:name]}](#{e[:path]})" }
    f.puts
    f.puts '## Classes'
    f.puts
    classes.sort_by { |e| e[:name] }.each { |e| f.puts "- [#{e[:name]}](#{e[:path]})" }
  end
end

namespace :docs do
  desc 'Generate YARD markdown into docs/reference/'
  task :generate do
    require 'fileutils'
    output_dir = 'docs/reference'
    FileUtils.rm_rf(output_dir)
    FileUtils.mkdir_p(output_dir)
    sh 'bundle exec yardoc --plugin markdown --format markdown --output-dir docs/reference gem/*/lib/**/*.rb'
    generate_reference_index(output_dir)
  end

  desc 'Generate docs and serve locally with MkDocs'
  task serve: :generate do
    sh 'mkdocs serve'
  end
end
