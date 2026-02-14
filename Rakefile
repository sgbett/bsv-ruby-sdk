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
    output_dir = 'docs/reference'
    FileUtils.rm_rf(output_dir)
    FileUtils.mkdir_p(output_dir)
    sh 'bundle exec yardoc --plugin markdown --format markdown --output-dir docs/reference lib/**/*.rb'
  end

  desc 'Generate docs and serve locally with MkDocs'
  task serve: :generate do
    sh 'mkdocs serve'
  end
end
