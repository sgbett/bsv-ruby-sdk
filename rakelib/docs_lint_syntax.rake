# frozen_string_literal: true

# docs:lint:syntax — Compile every ```ruby block in hand-authored markdown through
# RubyVM::InstructionSequence to catch syntax errors.
#
# Opt-outs:
#
#   # illustrative         — first line of a fenced block: skip this block entirely.
#                            Use for snippets that are deliberately incomplete or
#                            show pseudo-code rather than runnable Ruby.
#
#   <!-- docs:lint:ignore Symbol -->  — anywhere in a file: skip the whole file.

namespace :docs do
  namespace :lint do
    desc 'Compile ```ruby blocks in docs and check for syntax errors'
    task :syntax do
      errors = DocsLint::Syntax.check
      if errors.empty?
        puts "docs:lint:syntax — OK (#{DocsLint::Syntax.blocks_checked} block(s) checked)"
      else
        errors.each { |e| warn e }
        exit 1
      end
    end
  end
end

module DocsLint
  # Compiles every ```ruby block through RubyVM::InstructionSequence.
  module Syntax
    IGNORE_COMMENT = '<!-- docs:lint:ignore Symbol -->'

    class << self
      attr_reader :blocks_checked

      def check
        @blocks_checked = 0
        errors = []

        lint_files.each do |path|
          content = File.read(path)
          next if content.include?(IGNORE_COMMENT)

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

      # Extract fenced ```ruby blocks and compile each one.
      def check_file(path, content)
        errors = []
        pos    = 0

        while (fence_m = content.match(/^```ruby\s*\n(.*?)^```/m, pos))
          block_start = fence_m.pre_match.count("\n") + 2
          block_body  = fence_m[1]
          pos         = fence_m.end(0)

          # Honour the `# illustrative` opt-out
          next if block_body.match?(/\A\s*#\s*illustrative\b/)

          @blocks_checked += 1
          err = compile_block(path, block_start, block_body)
          errors << err if err
        end

        errors
      end

      # Compile a single code block through RubyVM::InstructionSequence.
      # Returns an error string on SyntaxError, nil on success.
      def compile_block(path, block_start_line, block_body)
        verbose_was = $VERBOSE
        $VERBOSE = nil
        begin
          RubyVM::InstructionSequence.compile(block_body)
          nil
        rescue SyntaxError => e
          # RubyVM reports lines relative to the block; add the file offset.
          # Block form so +Regexp.last_match+ sees this match, not a stale prior one.
          msg = e.message
                 .sub(/\(eval\):(\d+):/) { "(eval):#{block_start_line + ::Regexp.last_match(1).to_i - 1}:" }
                 .gsub(/^.*\(eval\):\d+:.*\n/, '') # strip caret lines
                 .lines.first.to_s.strip

          "#{path}:#{block_start_line}: Ruby syntax error: #{msg}"
        ensure
          $VERBOSE = verbose_was
        end
      end
    end
  end
end
