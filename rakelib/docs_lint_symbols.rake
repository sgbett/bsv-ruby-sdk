# frozen_string_literal: true

# docs:lint:symbols — Verify that every BSV:: constant referenced in hand-authored
# markdown files resolves to a real class, module, or constant in the gem's lib tree.
#
# Opt-out per-file: add the following HTML comment anywhere in a file to suppress
# ALL symbol errors for that file:
#
#   <!-- docs:lint:ignore Symbol -->
#
# Use sparingly; add a prose comment next to the directive explaining why.

namespace :docs do
  namespace :lint do
    desc 'Check BSV:: constants in docs resolve to real classes/modules/constants'
    task :symbols do
      errors = DocsLint::Symbols.check
      if errors.empty?
        puts "docs:lint:symbols — OK (#{DocsLint::Symbols.files_checked} file(s) checked)"
      else
        errors.each { |e| warn e }
        exit 1
      end
    end
  end
end

module DocsLint
  # Extracts and validates BSV:: constant references from markdown files.
  module Symbols
    # Matches any BSV::<Name> token, including chained qualifiers.
    CONSTANT_RE = /BSV(?:::[A-Z][A-Za-z0-9_]*)+/
    IGNORE_COMMENT = '<!-- docs:lint:ignore Symbol -->'

    # Lines that open a new `end`-consuming scope but are not module/class.
    # Kept at module level so the constant is not scoped to the singleton class.
    END_CONSUMING_RE = /
      \A(?:
        def\s              |  # method definition
        begin\b            |  # begin…rescue…ensure…end
        do\b               |  # do…end block literal
        \w.*\bdo\b\s*(?:\|.*\|)?\s*$ |  # method call with trailing do
        if\b               |  # if…elsif…else…end
        unless\b           |  # unless…end
        while\b            |  # while…end
        until\b            |  # until…end
        for\b              |  # for…in…end
        case\b             |  # case…when…end
        class\s*<<\s*\w       # singleton class reopening
      )
    /x

    class << self
      attr_reader :files_checked

      def check
        @files_checked = 0
        known = build_known_constants
        errors = []

        lint_files.each do |path|
          content = File.read(path)
          next if content.include?(IGNORE_COMMENT)

          @files_checked += 1
          content.each_line.with_index(1) do |line, lineno|
            tokens_on(line).each do |token|
              errors << "#{path}:#{lineno}: undefined constant #{token}" unless known.include?(token)
            end
          end
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

      # Extract BSV:: tokens from a single line, stripping HTML comments first
      # so ignore directives don't suppress tokens on the same line.
      def tokens_on(line)
        cleaned = line.gsub(/<!--.*?-->/, '')
        cleaned.scan(CONSTANT_RE)
      end

      # Build the set of all known fully-qualified BSV:: constants by walking
      # every .rb file in gem/bsv-sdk/lib and tracking module/class nesting.
      def build_known_constants
        project_root = File.expand_path('..', __dir__)
        lib_root     = File.join(project_root, 'gem', 'bsv-sdk', 'lib')
        known = Set.new

        Dir.glob(File.join(lib_root, '**', '*.rb')).each do |rb_path|
          extract_constants(File.read(rb_path)).each { |c| known.add(c) }
        end

        known
      end

      # Walk a Ruby source file line-by-line, maintaining a namespace stack,
      # and emit fully-qualified constant names for every module/class/constant
      # declaration encountered.
      #
      # Tracks `module`/`class` pushes and `def`/`do`/`begin`/`if`/etc. pushes
      # so that `end` keywords are correctly attributed. Correctly handles:
      #   - Multi-level qualified names: `module BSV::Transaction` pushes two levels
      #   - Single-line class declarations: `class Foo; end` — push + immediate pop
      #   - Constant assignments inside namespaces: `CONST = ...`
      #   - Qualified top-level assignments: `BSV::Foo::Bar = ...`
      #
      # Not a full Ruby parser — but sufficient for the SDK's consistent style.
      def extract_constants(source)
        constants = []

        # `ns_stack` is the current namespace path, e.g. ['BSV', 'Transaction'].
        # `end_stack` is a parallel stack of symbols: `:ns` when a module/class
        # was pushed, `:block` for every other `end`-consuming construct (def,
        # do, begin, if, unless, while, until, for, case, rescue, ensure, else,
        # defined?, proc, lambda).  We only pop `ns_stack` when we see `:ns`.
        ns_stack  = []
        end_stack = []

        source.each_line do |raw_line|
          line = raw_line.strip
          next if line.empty? || line.start_with?('#')

          # --- Single-line class/module (ends with `; end`) --------------------
          # e.g. `class Foo < Bar; end` or `class Error < StandardError; end`
          # Register the constant but do not push to stacks.
          if (m = line.match(/\A(?:class|module)\s+([A-Z][A-Za-z0-9_:]*)/)) &&
             line.match(/;\s*end\s*(?:#.*)?$/)
            parts = m[1].split('::')
            parts.length.times do |i|
              slice = (ns_stack + parts)[0, ns_stack.length + i + 1]
              full  = slice.join('::')
              constants << full if full.start_with?('BSV::') || full == 'BSV'
            end
            next
          end

          # --- Multi-line class/module ------------------------------------------
          if (m = line.match(/\A(?:class|module)\s+([A-Z][A-Za-z0-9_:]*)/))
            parts = m[1].split('::')
            parts.each { |p| ns_stack << p }
            parts.length.times do |i|
              slice = ns_stack[0, ns_stack.length - parts.length + i + 1]
              full  = slice.join('::')
              constants << full if full.start_with?('BSV::') || full == 'BSV'
            end
            end_stack << [:ns, parts.length]
            next
          end

          # --- Qualified top-level constant assignment: BSV::Foo::Bar = ... ----
          if (m = line.match(/\A(BSV(?:::[A-Z][A-Za-z0-9_]*)+)\s*=(?!=)/))
            constants << m[1]
            # No `end` will follow, so skip push
          end

          # --- Bare constant assignment inside a BSV namespace -----------------
          # e.g. `ALL_FORK_ID = ALL | FORK_ID` inside `module Sighash`
          if ns_stack.first == 'BSV' &&
             (m = line.match(/\A([A-Z_][A-Z0-9_]*)\s*=(?!=)/)) &&
             !line.match(/\A(?:class|module|def)\s/)
            full = (ns_stack + [m[1]]).join('::')
            constants << full
          end

          # --- def / do-block / begin / if / case etc. push a :block entry ----
          # These consume an `end` but don't alter the namespace.
          if end_consuming?(line)
            end_stack << [:block, 1]
            next
          end

          # --- `end` pops the most recent entry --------------------------------
          next unless line == 'end' || line.start_with?('end ') || line.start_with?('end#')
          next unless end_stack.any?

          kind, count = end_stack.pop
          count.times { ns_stack.pop } if kind == :ns
          # :block entries just consume the `end`
        end

        constants
      end

      def end_consuming?(line)
        return false if line.match(/\A(?:class|module)\s/) # already handled

        # Single-line forms don't consume an end at block level
        return false if line.match(/;\s*end\s*(?:#.*)?$/)

        line.match?(END_CONSUMING_RE)
      end
    end
  end
end
