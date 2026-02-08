# frozen_string_literal: true

Bundler::GemHelper.install_tasks(name: 'bsv-sdk')
Bundler::GemHelper.install_tasks(name: 'bsv-attest')
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec
