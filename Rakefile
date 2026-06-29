# frozen_string_literal: true

# Gem releases are handled by the /release Claude Code skill.
# See CLAUDE.md for the release workflow and tag conventions.

require 'rspec/core/rake_task'

namespace :spec do
  {
    'sdk' => 'bsv-sdk',
    'attest' => 'bsv-attest'
  }.each do |gem_key, gem_dir|
    RSpec::Core::RakeTask.new(gem_key) do |t|
      t.pattern = "gem/#{gem_dir}/spec/**/*_spec.rb"
      t.rspec_opts = "--default-path gem/#{gem_dir}/spec"
    end
  end
end

desc 'Run all specs across all gems'
task spec: %i[spec:sdk spec:attest]
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

namespace :docs do # rubocop:disable Metrics/BlockLength
  desc 'Generate YARD markdown into docs/reference/api/'
  task :generate do
    require 'fileutils'
    # YARD output lives in its own +api/+ sub-dir per the documentation
    # strategy. Authored canonical-reference content (blueprints, principles,
    # state-machine refs) sits at +docs/reference/+ as siblings; scoping the
    # rm_rf to +api/+ keeps the authored docs out of the nuclear cleanup.
    output_dir = 'docs/reference/api'
    FileUtils.rm_rf(output_dir)
    FileUtils.mkdir_p(output_dir)
    sh "bundle exec yardoc --plugin markdown --format markdown --output-dir #{output_dir} gem/*/lib/**/*.rb"
    generate_reference_index(output_dir)
  end

  desc 'Generate protocol reference docs from source into docs/network/protocols/'
  task :protocols do # rubocop:disable Metrics/BlockLength
    require 'fileutils'

    protocols_src = Dir['gem/bsv-sdk/lib/bsv/network/protocols/*.rb']
    output_dir    = 'docs/network/protocols'
    FileUtils.mkdir_p(output_dir)

    protocols_src.each_with_index do |src_path, idx| # rubocop:disable Metrics/BlockLength
      source      = File.read(src_path)
      class_name  = File.basename(src_path, '.rb')
      out_file    = File.join(output_dir, "#{class_name}.md")
      nav_order   = idx + 1

      # --- Extract class-level description and @see URL -----------------------
      # The class doc is the comment block immediately before the class line.
      class_block = source[/(?:(?:^  +#[^\n]*\n)+)(?=  +class \w)/]
      description = ''
      see_url     = nil
      see_text    = nil

      if class_block
        lines = class_block.split("\n").map { |l| l.sub(/\A\s*#\s?/, '') }
        see_line = lines.find { |l| l.start_with?('@see ') }
        if see_line
          parts    = see_line.sub('@see ', '').split(' ', 2)
          see_url  = parts[0]
          see_text = parts[1]
        end
        # Description: first non-blank lines before any == or @tag
        desc_lines = []
        lines.each do |l|
          break if l.start_with?('==', '@', '=')
          break if l.strip.empty? && !desc_lines.empty?

          desc_lines << l unless l.strip.empty? && desc_lines.empty?
        end
        description = desc_lines.join(' ').strip
      end

      # --- Extract endpoint declarations --------------------------------------
      # Handles single-line and multi-line declarations. The endpoint macro
      # may span two lines when the response: keyword is on a continuation line,
      # e.g.:
      #   endpoint :current_height, :get, '/tip',
      #            response: ->(body) { JSON.parse(body)['height'] }
      #
      # Strategy: collapse all whitespace-continuation pairs, then scan for the
      # full endpoint pattern in the normalised source.
      normalised = source.gsub(/,\s*\n\s+/, ', ')
      endpoint_re = /endpoint\s+:(\w+)\s*,\s*:(\w+)\s*,\s*['"]([^'"]+)['"](.*?)(?=\n)/
      endpoints = normalised.scan(endpoint_re).map do |name, method, path, tail|
        response =
          if tail =~ /response:\s*(->\s*\([^)]*\)\s*\{[^}]*\})/
            Regexp.last_match(1).strip
          elsif tail =~ /response:\s*(:[a-z_]+)/
            Regexp.last_match(1)
          end
        handler =
          if response.nil?
            ':raw'
          elsif response.start_with?('->')
            'lambda'
          else
            response
          end
        { name: name, method: method.upcase, path: path, response: handler }
      end

      # --- Extract escape hatch methods and their doc comments ----------------
      # Match def call_<name> and capture the comment block above it.
      # Build the first complete sentence from doc lines (stop at period or @tag).
      escape_hatches = []
      source.scan(/(?:((?:[ \t]*#[^\n]*\n)+))[ \t]*def (call_\w+)/) do |comment_block, method_name|
        cmd = method_name.sub('call_', '')
        lines = comment_block.split("\n").map { |l| l.sub(/\A\s*#\s?/, '').strip }
        # Collect lines until a YARD tag, empty line boundary, or sentence end
        doc_lines = []
        lines.each do |l|
          break if l.start_with?('@')
          break if l.strip.empty? && !doc_lines.empty?
          next if l.strip.empty?

          doc_lines << l
          break if l.end_with?('.')
        end
        first_sentence = doc_lines.join(' ').gsub(/\+([^+]+)\+/, '`\1`').strip
        escape_hatches << { command: cmd, doc: first_sentence }
      end

      # --- Build a human-readable protocol name ------------------------------
      # Brand-correct overrides for known protocols; otherwise split-on-_ and
      # capitalise each word, with per-word brand shortcuts (WoC, REST, TAAL,
      # ARC) applied case-insensitively.
      brand_overrides = {
        'jungle_bus' => 'JungleBus'
      }
      proto_display = brand_overrides[class_name] || class_name
                      .gsub('_', ' ')
                      .split
                      .map do |w|
        case w.downcase
        when 'woc'    then 'WoC'
        when 'rest'   then 'REST'
        when 'taal'   then 'TAAL'
        when 'arc'    then 'ARC'
        else w.capitalize
        end
      end.join(' ')

      # --- Render markdown ----------------------------------------------------
      File.open(out_file, 'w') do |f| # rubocop:disable Metrics/BlockLength
        # Jekyll frontmatter — required by just-the-docs nav and docs:lint.
        # Emitted by the generator so re-runs preserve nav ordering rather
        # than silently stripping hand-added frontmatter.
        f.puts '---'
        f.puts "title: #{proto_display}"
        f.puts "nav_order: #{nav_order}"
        f.puts 'parent: Protocol Reference'
        f.puts '---'
        f.puts
        f.puts '<!-- Generated by: bundle exec rake docs:protocols -->'
        f.puts
        f.puts "# #{proto_display}"
        f.puts
        f.puts description unless description.empty?
        f.puts
        if see_url
          link_label = see_text || 'External API documentation'
          f.puts "**External docs:** [#{link_label}](#{see_url})"
          f.puts
        end

        # Commands table
        f.puts '## Commands'
        f.puts
        f.puts '| Command | Method | Path | Response | Escape hatch |'
        f.puts '|---------|--------|------|----------|--------------|'

        escape_names = escape_hatches.map { |e| e[:command] }
        endpoints.each do |ep|
          has_hatch = escape_names.include?(ep[:name])
          f.puts "| `#{ep[:name]}` | #{ep[:method]} | `#{ep[:path]}` | #{ep[:response]} | #{'yes' if has_hatch} |"
        end

        # Escape hatches section (only when any exist)
        unless escape_hatches.empty?
          f.puts
          f.puts '## Escape Hatches'
          f.puts
          f.puts 'These commands use custom dispatch logic rather than the default HTTP template.'
          f.puts
          escape_hatches.each do |eh|
            f.puts "### `#{eh[:command]}`"
            f.puts
            f.puts eh[:doc] unless eh[:doc].empty?
            f.puts
          end
        end
      end

      puts "  generated #{out_file} (#{endpoints.size} endpoints, #{escape_hatches.size} escape hatches)"
    end
  end

  desc 'Generate provider × protocol matrix into docs/network/protocols/index.md'
  task providers: :protocols do # rubocop:disable Metrics/BlockLength
    require 'fileutils'

    providers_src = Dir['gem/bsv-sdk/lib/bsv/network/providers/*.rb']
    output_dir    = 'docs/network/protocols'
    FileUtils.mkdir_p(output_dir)

    # --- Canonical protocol order and display names ----------------------------
    protocol_order = %w[ARC WoCREST Chaintracks Ordinals JungleBus TAALBinary]
    protocol_display = {
      'ARC' => 'ARC',
      'WoCREST' => 'WoCREST',
      'Chaintracks' => 'Chaintracks',
      'Ordinals' => 'Ordinals',
      'JungleBus' => 'JungleBus',
      'TAALBinary' => 'TAALBinary',
      'Arcade' => 'Arcade'
    }
    # Display name overrides for provider class names derived from filenames
    provider_display = {
      'Taal' => 'TAAL',
      'GorillaPool' => 'GorillaPool',
      'WhatsOnChain' => 'WhatsOnChain'
    }
    protocol_file = {
      'ARC' => 'arc.md',
      'WoCREST' => 'woc_rest.md',
      'Chaintracks' => 'chaintracks.md',
      'Ordinals' => 'ordinals.md',
      'JungleBus' => 'jungle_bus.md',
      'TAALBinary' => 'taal_binary.md',
      'Arcade' => 'arcade.md'
    }

    # --- Parse each provider factory file --------------------------------------
    # For each factory method (mainnet/testnet/stn/default) extract the
    # Protocols:: class names from p.protocol lines.
    providers = []
    providers_src.each do |src_path|
      source         = File.read(src_path)
      provider_class = File.basename(src_path, '.rb')
                           .split('_').map(&:capitalize).join

      # Collect network → [protocol names] from def self.<network> blocks.
      # Strategy: scan for def self.<name> ... end blocks, then find all
      # p.protocol Protocols::<Name> lines within each block.
      networks = {}
      source.scan(/def self\.(\w+).*?\n(.*?)(?=\n\s+def |\z)/m) do |method_name, body|
        next if method_name == 'default'

        protocols_used = body.scan(/p\.protocol\s+Protocols::(\w+)/).flatten
        networks[method_name] = protocols_used unless protocols_used.empty?
      end

      providers << {
        class_name: provider_class,
        file: File.basename(src_path, '.rb'),
        networks: networks
      }
    end

    # --- Collect endpoint counts from already-generated protocol docs ----------
    endpoint_counts = {}
    protocol_order.each do |proto|
      doc_path = File.join(output_dir, protocol_file[proto])
      next unless File.exist?(doc_path)

      count = File.readlines(doc_path).count { |l| l.start_with?('| `') }
      endpoint_counts[proto] = count
    end

    # --- Detect command overlap across protocols --------------------------------
    # Parse endpoint names per protocol from the generated docs.
    protocol_commands = {}
    protocol_order.each do |proto|
      doc_path = File.join(output_dir, protocol_file[proto])
      next unless File.exist?(doc_path)

      cmds = File.readlines(doc_path)
                 .select { |l| l.start_with?('| `') }
                 .map { |l| l.match(/\| `(\w+)`/)[1] }
      protocol_commands[proto] = cmds
    end
    all_commands = protocol_commands.values.flatten
    overlap = all_commands.tally.select { |_, count| count > 1 }
    overlapping_commands = overlap.keys.sort.map do |cmd|
      served_by = protocol_order.select { |p| (protocol_commands[p] || []).include?(cmd) }
      { command: cmd, protocols: served_by }
    end

    # --- Render markdown -------------------------------------------------------
    out_file = File.join(output_dir, 'index.md')
    File.open(out_file, 'w') do |f| # rubocop:disable Metrics/BlockLength
      # Jekyll frontmatter — required by just-the-docs nav and docs:lint.
      # Emitted by the generator so re-runs preserve nav structure rather
      # than silently stripping hand-added frontmatter.
      f.puts '---'
      f.puts 'title: Protocol Reference'
      f.puts 'nav_order: 3'
      f.puts 'parent: Network'
      f.puts 'has_children: true'
      f.puts '---'
      f.puts
      f.puts '<!-- Generated by: bundle exec rake docs:providers -->'
      f.puts
      f.puts '# Network Protocol Reference'
      f.puts
      f.puts 'Auto-generated from source. Run `bundle exec rake docs:providers` to regenerate.'
      f.puts

      # Summary table: protocol → endpoint count + link
      f.puts '## Protocols'
      f.puts
      f.puts '| Protocol | Endpoints | Detail |'
      f.puts '|----------|-----------|--------|'
      protocol_order.each do |proto|
        count = endpoint_counts[proto] || 0
        link  = "[#{protocol_display[proto]}](#{protocol_file[proto]})"
        f.puts "| #{protocol_display[proto]} | #{count} | #{link} |"
      end
      f.puts

      # Provider × protocol matrix
      f.puts '## Provider Matrix'
      f.puts
      f.puts 'Each cell shows the networks on which the provider composes that protocol.'
      f.puts
      header_protos = protocol_order.map { |p| protocol_display[p] }
      f.puts "| Provider | #{header_protos.join(' | ')} |"
      f.puts "| --- | #{protocol_order.map { '---' }.join(' | ')} |"

      providers.each do |prov|
        # Collect per-protocol network list
        cells = protocol_order.map do |proto|
          nets = prov[:networks].select { |_net, protos| protos.include?(proto) }.keys
          nets.empty? ? '' : nets.join(', ')
        end
        display = provider_display.fetch(prov[:class_name], prov[:class_name])
        f.puts "| #{display} | #{cells.join(' | ')} |"
      end
      f.puts

      # Provider detail section
      f.puts '## Provider Details'
      f.puts
      providers.each do |prov|
        display = provider_display.fetch(prov[:class_name], prov[:class_name])
        f.puts "### #{display}"
        f.puts
        all_nets = prov[:networks].keys
        f.puts "**Available networks:** #{all_nets.join(', ')}"
        f.puts

        total_cmds = prov[:networks].values.flatten.uniq.sum do |proto|
          endpoint_counts[proto] || 0
        end
        f.puts "**Total commands:** #{total_cmds} (across all composed protocols)"
        f.puts

        f.puts '| Network | Protocols |'
        f.puts '|---------|-----------|'
        prov[:networks].each do |net, protos|
          proto_links = protos.map { |p| "[#{protocol_display[p]}](#{protocol_file[p]})" }
          f.puts "| #{net} | #{proto_links.join(', ')} |"
        end
        f.puts
      end

      # Command overlap table
      unless overlapping_commands.empty?
        f.puts '## Command Overlap'
        f.puts
        f.puts 'Commands that appear in more than one protocol. The first-registered protocol ' \
               'wins when a provider composes multiple protocols.'
        f.puts
        f.puts '| Command | Protocols |'
        f.puts '|---------|-----------|'
        overlapping_commands.each do |ov|
          proto_links = ov[:protocols].map { |p| "[#{protocol_display[p]}](#{protocol_file[p]})" }
          f.puts "| `#{ov[:command]}` | #{proto_links.join(', ')} |"
        end
        f.puts
      end
    end

    puts "  generated #{out_file} (#{providers.size} providers, #{overlapping_commands.size} overlapping commands)"
  end
  desc 'Build the Jekyll docs site'
  task :build do
    Dir.chdir('docs') { sh 'BUNDLE_GEMFILE=Gemfile bundle exec jekyll build' }
  end

  desc 'Serve the Jekyll docs locally'
  task :serve do
    Dir.chdir('docs') { sh 'BUNDLE_GEMFILE=Gemfile bundle exec jekyll serve --livereload' }
  end

  desc 'Lint docs frontmatter — asserts required keys on every hand-authored .md'
  task :lint do # rubocop:disable Metrics/BlockLength
    require 'yaml'

    docs_root = File.expand_path('docs', __dir__)

    # Exclude generated and non-content paths:
    #   _site/        — Jekyll output, not source
    #   reference/api/ — YARD-generated, no hand-authored frontmatter
    #   vendor/       — CI bundler-cache lands gems here; their READMEs
    #                   are not our docs
    #   .bundle/      — Bundler config dir
    #   README.md     — contributor meta-documentation, not a site page
    excluded_prefixes = [
      File.join(docs_root, '_site'),
      File.join(docs_root, 'reference', 'api'),
      File.join(docs_root, 'vendor'),
      File.join(docs_root, '.bundle')
    ]
    excluded_files = [File.join(docs_root, 'README.md')]

    md_files = Dir.glob(File.join(docs_root, '**', '*.md')).reject do |f|
      excluded_prefixes.any? { |prefix| f.start_with?(prefix) } ||
        excluded_files.include?(f)
    end

    errors = []

    md_files.each do |path|
      content = File.read(path)

      unless content.start_with?('---')
        errors << "#{path}: missing frontmatter block (file must begin with ---)"
        next
      end

      # Extract the YAML between the opening and closing --- delimiters.
      fm_match = content.match(/\A---\s*\n(.*?)\n---/m)
      unless fm_match
        errors << "#{path}: malformed frontmatter (no closing ---)"
        next
      end

      fm = YAML.safe_load(fm_match[1]) || {}

      # Every file must declare a title.
      unless fm['title']
        errors << "#{path}: missing required frontmatter key: title"
        next
      end

      # nav_order is required for every nav-bearing page. Without it,
      # just-the-docs falls back to alphabetical, which silently breaks the
      # MkDocs nav order this migration preserves. Stubs hidden from nav
      # (nav_exclude: true) and the root index are the only exemptions.
      is_root_index = path == File.join(docs_root, 'index.md')
      unless fm['nav_exclude'] || is_root_index || fm['nav_order']
        errors << "#{path}: missing required frontmatter key: nav_order"
        next
      end

      # The index page is the root anchor — no parent/nav_exclude required.
      next if is_root_index

      # Section landing pages (has_children: true) are also top-level — they
      # act as parents and need no parent key themselves.
      next if fm['has_children']

      # Every other page must declare either a parent (placing it in a section)
      # or nav_exclude: true (hiding it from the nav entirely, e.g. redirect stubs).
      next if fm['parent'] || fm['nav_exclude']

      errors << "#{path}: missing 'parent' or 'nav_exclude' — " \
                'non-root, non-section pages must declare one or the other'
    end

    if errors.empty?
      puts "docs:lint — #{md_files.size} file(s) checked, all OK"
    else
      errors.each { |e| warn e }
      exit 1
    end
  end

  desc 'Check internal links and anchors in the built site (offline)'
  task proofread: :build do
    Dir.chdir('docs') do
      # html-proofer is Jekyll-aware: swap_urls strips the baseurl prefix
      # (which is a URL concept, not a filesystem path) so root-relative
      # links like /bsv-ruby-sdk/sdk/wallet/ resolve to _site/sdk/wallet/.
      # disable_external skips https:// links — those need network.
      sh 'BUNDLE_GEMFILE=Gemfile bundle exec htmlproofer _site ' \
         '--disable-external ' \
         '--swap-urls "^/bsv-ruby-sdk:" ' \
         '--ignore-empty-alt ' \
         '--ignore-missing-alt ' \
         '--allow-missing-href'
    end
  end
end
