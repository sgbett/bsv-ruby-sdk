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
#
# Companion-gem references (e.g. BSV::Wallet::Client, which lives in the
# separate bsv-wallet repo) are whitelisted via +.docs-lint.yml+ at the
# repo root.

require 'prism'
require 'yaml'

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

    # Companion-gem whitelist, loaded from +.docs-lint.yml+ at repo root.
    # Contributors edit the YAML file rather than this source when a legitimate
    # cross-repo constant reference lands in the docs — see that file's header
    # for the rationale on why this list stays small and explicit.
    KNOWN_EXTERNAL = begin
      config_path = File.expand_path('../.docs-lint.yml', __dir__)
      config = File.exist?(config_path) ? YAML.safe_load_file(config_path) : {}
      Set.new((config || {})['known_external'] || [])
    end.freeze

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
              next if known.include?(token) || KNOWN_EXTERNAL.include?(token)

              errors << "#{path}:#{lineno}: undefined constant #{token}"
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

      # Parse a Ruby source file with Prism and emit fully-qualified constant
      # names for every module, class, and constant declaration inside a BSV
      # namespace. Prism gives us correct scope tracking for free — no need to
      # count +end+ keywords by hand.
      #
      # Handles:
      #   - Multi-level qualified declarations: +module BSV::Transaction+
      #   - Nested modules and classes
      #   - Bare constant assignments (SCREAMING_SNAKE and PascalCase aliases)
      #   - Qualified top-level assignments: +BSV::Foo::Bar = ...+
      def extract_constants(source)
        result = Prism.parse(source)
        return [] if result.failure?

        constants = []
        walk_ast(result.value, [], constants)
        constants
      end

      # AST traversal. +ns_stack+ is the enclosing namespace path from the file
      # root, e.g. +['BSV', 'Transaction']+ inside +module BSV; module Transaction+.
      def walk_ast(node, ns_stack, constants)
        return if node.nil?

        case node
        when Prism::ModuleNode, Prism::ClassNode
          parts = flatten_constant_path(node.constant_path)
          # For +module BSV::Foo::Bar+ (with ns_stack=[]) emit each ancestor:
          # +BSV+, +BSV::Foo+, +BSV::Foo::Bar+.
          parts.each_index do |i|
            full = (ns_stack + parts[0..i]).join('::')
            constants << full if bsv_scoped?(full)
          end
          walk_ast(node.body, ns_stack + parts, constants)

        when Prism::ConstantWriteNode
          # +CONST = ...+ — the parser only emits this when the LHS is a bare
          # constant, so no path flattening needed. Only emit inside a BSV::
          # namespace; a bare top-level constant assignment isn't in scope.
          constants << (ns_stack + [node.name.to_s]).join('::') if ns_stack.first == 'BSV'

        when Prism::ConstantPathWriteNode
          # +BSV::Foo::Bar = ...+ regardless of enclosing scope.
          full = flatten_constant_path(node.target).join('::')
          constants << full if bsv_scoped?(full)

        else
          node.child_nodes.compact.each { |child| walk_ast(child, ns_stack, constants) }
        end
      end

      # Reduce a ConstantPathNode / ConstantReadNode chain to an array of
      # simple name strings, dropping any leading +::+ (absolute reference).
      def flatten_constant_path(node)
        case node
        when Prism::ConstantReadNode
          [node.name.to_s]
        when Prism::ConstantPathNode
          parent = node.parent ? flatten_constant_path(node.parent) : []
          parent + [node.name.to_s]
        else
          []
        end
      end

      def bsv_scoped?(full)
        full == 'BSV' || full.start_with?('BSV::')
      end
    end
  end
end
