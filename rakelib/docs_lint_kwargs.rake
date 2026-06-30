# frozen_string_literal: true

# docs:lint:kwargs — Verify that documented `BSV::Foo.new(kw: ...)` calls in fenced
# ```ruby blocks use only keyword arguments that exist on the target class's
# `def initialize`.
#
# Uses the same file set and opt-out mechanism as docs:lint:symbols.

namespace :docs do
  namespace :lint do
    desc 'Check .new() kwarg names in docs match def initialize signatures'
    task :kwargs do
      errors = DocsLint::Kwargs.check
      if errors.empty?
        puts "docs:lint:kwargs — OK (#{DocsLint::Kwargs.files_checked} file(s) checked)"
      else
        errors.each { |e| warn e }
        exit 1
      end
    end
  end
end

module DocsLint
  # Checks keyword arguments in BSV::Foo.new(...) calls inside ```ruby blocks.
  module Kwargs
    IGNORE_COMMENT = '<!-- docs:lint:ignore Symbol -->'

    # Matches `BSV::Foo::Bar.new(` possibly spanning multiple lines inside a block.
    NEW_CALL_RE = /BSV(?:::[A-Z][A-Za-z0-9_]*)+\.new\s*\(/m

    class << self
      attr_reader :files_checked

      def check
        @files_checked = 0
        errors = []

        lint_files.each do |path|
          content = File.read(path)
          next if content.include?(IGNORE_COMMENT)

          @files_checked += 1
          errors.concat(check_file(path, content))
        end

        errors
      end

      private

      def lint_files
        project_root = File.expand_path('..', __dir__)
        docs_root    = File.join(project_root, 'docs')

        excluded_prefixes = [
          File.join(docs_root, '_site'),
          File.join(docs_root, 'reference', 'api'),
          File.join(docs_root, 'vendor'),
          File.join(docs_root, '.bundle')
        ]

        doc_files = Dir.glob(File.join(docs_root, '**', '*.md')).reject do |f|
          excluded_prefixes.any? { |prefix| f.start_with?("#{prefix}/") } ||
            redirect_stub?(f)
        end

        readme_files = [
          File.join(project_root, 'README.md'),
          File.join(project_root, 'gem', 'bsv-sdk', 'README.md')
        ].select { |f| File.exist?(f) }

        doc_files + readme_files
      end

      def redirect_stub?(path)
        content = File.read(path)
        return false unless content.start_with?('---')

        fm = content.match(/\A---\s*\n(.*?)\n---/m)
        fm ? fm[1].include?('redirect_to:') : false
      end

      # Extract fenced ```ruby blocks from a file and check each .new() call.
      def check_file(path, content)
        errors = []
        # Track line offset of each fenced block's opening fence
        pos    = 0
        text   = content

        while (fence_m = text.match(/^```ruby\s*\n(.*?)^```/m, pos))
          block_start = fence_m.pre_match.count("\n") + 2 # line of first code line
          block_body  = fence_m[1]

          # Skip illustrative blocks
          errors.concat(check_block(path, block_start, block_body)) unless block_body.match?(/\A\s*#\s*illustrative\b/)

          pos = fence_m.end(0)
        end

        errors
      end

      # Scan a single fenced block for .new() calls and validate their kwargs.
      def check_block(path, block_start_line, block_body)
        errors = []

        # Collapse multi-line .new( ... ) calls into a single string.
        # Strategy: scan for `BSV::Foo.new(` then accumulate lines until
        # parentheses are balanced.
        lines = block_body.lines

        lines.each_with_index do |line, idx|
          lineno = block_start_line + idx

          # Find start of a .new( call on this line
          m = line.match(/(BSV(?:::[A-Z][A-Za-z0-9_]*)+)\.new\s*\(/)
          next unless m

          const_name = m[1]
          call_start = m.end(0) - 1 # position of the opening `(`

          # Accumulate the argument list, handling multi-line calls
          full_call = collect_args(line[call_start..], lines, idx)
          kwargs    = extract_kwargs(full_call)
          next if kwargs.nil? || kwargs.empty?

          valid = initialize_kwargs(const_name)
          next if valid.nil? # class not found or accepts splat
          next if valid == :accepts_any

          unknown = kwargs - valid
          next if unknown.empty?

          errors << "#{path}:#{lineno}: unknown kwarg :#{unknown.first} for " \
                    "#{const_name}.new (valid: #{valid.map { |k| ":#{k}" }.join(', ')})"
        end

        errors
      end

      # Collect the argument string starting from the opening `(`, spanning
      # multiple continuation lines if needed, up to the balanced `)`.
      def collect_args(from_paren, all_lines, start_idx)
        depth  = 0
        result = +''

        # Start with the fragment from the current line
        candidates = [from_paren] + all_lines[(start_idx + 1)..]&.first(10).to_a

        candidates.each do |fragment|
          fragment.each_char do |ch|
            depth += 1 if ch == '('
            depth -= 1 if ch == ')'
            result << ch
            return result if depth.zero?
          end
        end

        result
      end

      # Extract keyword argument names from an argument list string like
      # `(prev_wtxid: ..., sequence: ...)`.
      def extract_kwargs(arg_string)
        # Remove string literals and nested parens to reduce noise
        cleaned = arg_string.gsub(/'[^']*'|"[^"]*"/, '""')
        cleaned.scan(/([a-z_][a-z_0-9]*):(?!:)/).flatten
      end

      # Return the set of keyword argument names accepted by `const_name.new`,
      # or `:accepts_any` if the signature uses **kwargs / *args, or `nil` if
      # the class file cannot be found or has no `def initialize`.
      def initialize_kwargs(const_name)
        rb_path = find_class_file(const_name)
        return nil unless rb_path

        source = File.read(rb_path)
        # Find `def initialize(...)` in the file
        m = source.match(/def\s+initialize\s*\(([^)]*)\)/)
        return nil unless m

        param_str = m[1]
        return :accepts_any if param_str.include?('**') || param_str.include?('*')

        # Extract keyword params: those followed by `:`
        param_str.scan(/([a-z_][a-z_0-9]*):/).flatten
      end

      # Map a fully-qualified constant name to the most likely source file.
      # Falls back to a glob-based search when snake_case guesses miss (e.g.
      # all-caps initialisms like P2PKH → p2pkh.rb, not p2_pkh.rb).
      def find_class_file(const_name)
        project_root = File.expand_path('..', __dir__)
        lib_root     = File.join(project_root, 'gem', 'bsv-sdk', 'lib')

        parts   = const_name.delete_prefix('BSV::').split('::')
        guesses = build_path_guesses(parts, lib_root)
        found   = guesses.find { |p| File.exist?(p) }
        return found if found

        # Glob fallback: search for any .rb containing `class <LeafName>`
        leaf = parts.last
        Dir.glob(File.join(lib_root, '**', '*.rb')).find do |f|
          File.read(f).match?(/(?:class|module)\s+#{Regexp.escape(leaf)}\b/)
        end
      end

      # Generate candidate file paths for a constant, deepest first.
      #
      # For BSV::Transaction::TransactionInput (parts = ['Transaction','TransactionInput']):
      #   1. gem/bsv-sdk/lib/bsv/transaction/transaction_input.rb  ← most specific
      #   2. gem/bsv-sdk/lib/bsv/transaction/transaction_input/transaction_input.rb
      #   3. gem/bsv-sdk/lib/bsv/transaction.rb
      def build_path_guesses(parts, lib_root)
        guesses = []

        # Most specific: all parts as directory path, last as file
        if parts.length >= 2
          dir  = parts[0..-2].map { |p| snake_case(p) }.join('/')
          file = snake_case(parts.last)
          guesses << File.join(lib_root, 'bsv', dir, "#{file}.rb")
          guesses << File.join(lib_root, 'bsv', dir, file, "#{file}.rb")
        end

        # Leaf as file directly under bsv/
        guesses << File.join(lib_root, 'bsv', "#{snake_case(parts.last)}.rb")

        # Full path as directory hierarchy (module rb files)
        full_dir = parts.map { |p| snake_case(p) }.join('/')
        guesses << File.join(lib_root, 'bsv', "#{full_dir}.rb")

        guesses.uniq
      end

      def snake_case(str)
        str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
      end
    end
  end
end
