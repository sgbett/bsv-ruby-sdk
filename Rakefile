# frozen_string_literal: true

Bundler::GemHelper.install_tasks(name: 'bsv-sdk')
Bundler::GemHelper.install_tasks(name: 'bsv-attest')
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

namespace :docs do
  desc 'Generate YARD markdown into docs/reference/'
  task :generate do
    require 'fileutils'
    require 'csv'
    output_dir = 'docs/reference'
    FileUtils.rm_rf(output_dir)
    FileUtils.mkdir_p(output_dir)
    sh 'bundle exec yardoc --plugin markdown --format markdown --output-dir docs/reference lib/**/*.rb'

    # Build reference/index.md from the CSV that yard-markdown produces
    csv_path = File.join(output_dir, 'index.csv')
    if File.exist?(csv_path)
      modules = []
      classes = []
      CSV.foreach(csv_path, headers: true) do |row|
        next unless row['type'] == 'Module' || row['type'] == 'Class'

        entry = { name: row['name'], path: row['path'], type: row['type'] }
        row['type'] == 'Module' ? modules << entry : classes << entry
      end

      File.open(File.join(output_dir, 'index.md'), 'w') do |f|
        f.puts '# API Reference'
        f.puts
        f.puts 'Auto-generated from source using [YARD](https://yardoc.org/).'
        f.puts
        f.puts '## Modules'
        f.puts
        modules.sort_by { |e| e[:name] }.each do |e|
          f.puts "- [#{e[:name]}](#{e[:path]})"
        end
        f.puts
        f.puts '## Classes'
        f.puts
        classes.sort_by { |e| e[:name] }.each do |e|
          f.puts "- [#{e[:name]}](#{e[:path]})"
        end
      end
    end
  end

  desc 'Generate docs and serve locally with MkDocs'
  task serve: :generate do
    sh 'mkdocs serve'
  end
end
