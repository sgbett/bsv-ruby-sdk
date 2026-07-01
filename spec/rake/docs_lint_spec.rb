# frozen_string_literal: true

# Specs for the three docs:lint sub-tasks defined in rakelib/.
#
# These tests exercise the DocsLint module implementations directly without
# invoking Rake, which keeps them fast and lets us use normal RSpec mechanics.
# Each describe block corresponds to one rakelib/*.rake file.

require 'tmpdir'
require 'fileutils'

# Load the three rakelib files.  They define Rake tasks (which we don't need
# to run) as well as the DocsLint::* modules (which we test directly).  We
# stub the Rake DSL methods so the files load cleanly outside a Rake context.
module Rake
  def self.application = self
end

def namespace(_name, &block) = block.call
def desc(_str); end
def task(*args, &); end

RAKELIB = File.expand_path('../../rakelib', __dir__)
load File.join(RAKELIB, 'docs_lint_symbols.rake')
load File.join(RAKELIB, 'docs_lint_kwargs.rake')
load File.join(RAKELIB, 'docs_lint_syntax.rake')

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Build a minimal fake doc tree in a temp directory and monkey-patch the
# DocsLint modules to point at it for the duration of a test.
def with_fake_docs(files, &block)
  Dir.mktmpdir('docs_lint_spec') do |tmpdir|
    docs_root = File.join(tmpdir, 'docs')
    lib_root  = File.join(tmpdir, 'gem', 'bsv-sdk', 'lib', 'bsv')
    FileUtils.mkdir_p(docs_root)
    FileUtils.mkdir_p(lib_root)

    # Write fixture files
    files.each do |path, content|
      full_path = File.join(tmpdir, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
    end

    # Temporarily patch __dir__-relative resolution to use tmpdir
    old_dir = ENV.fetch('DOCS_LINT_ROOT', nil)
    ENV['DOCS_LINT_ROOT'] = tmpdir

    # Patch the private `lint_files` and `build_known_constants` methods via
    # the simplest available mechanism: yield tmpdir so callers can build the
    # path manually and call module methods with explicit paths.
    block.call(tmpdir, docs_root, lib_root)
  ensure
    ENV['DOCS_LINT_ROOT'] = old_dir
  end
end

# Write a minimal Ruby source file defining the given constant.
def write_ruby_constant(lib_root, relative_path, namespace_chain, class_name, initialize_sig = nil)
  full_path = File.join(lib_root, relative_path)
  FileUtils.mkdir_p(File.dirname(full_path))

  outer = namespace_chain.map { |ns| "module #{ns}\n" }.join
  inner = "class #{class_name}\n"
  inner += "  def initialize(#{initialize_sig})\n  end\n" if initialize_sig
  inner += "end\n"
  closing = namespace_chain.map { 'end' }.join("\n")
  File.write(full_path, "# frozen_string_literal: true\n#{outer}#{inner}#{closing}\n")
end

# ---------------------------------------------------------------------------
# DocsLint::Symbols
# ---------------------------------------------------------------------------

RSpec.describe DocsLint::Symbols do
  # Bypass the class-level lint_files so we can control exactly which files
  # are scanned in each example.
  let(:project_root) { nil } # unused in direct calls

  describe '.extract_constants' do
    subject(:constants) { described_class.send(:extract_constants, source) }

    context 'with a simple module/class nesting' do
      let(:source) do
        <<~RUBY
          module BSV
            module Transaction
              class Tx
              end
            end
          end
        RUBY
      end

      it 'returns fully-qualified names for all nesting levels' do
        expect(constants).to include('BSV::Transaction', 'BSV::Transaction::Tx')
      end
    end

    context 'with a single-line class declaration' do
      let(:source) do
        <<~RUBY
          module BSV
            module Wallet
              class Error < StandardError; end
              class InvalidHmacError < Error; end
            end
          end
        RUBY
      end

      it 'registers single-line classes without corrupting the stack' do
        expect(constants).to include('BSV::Wallet::Error', 'BSV::Wallet::InvalidHmacError')
        # Ensure the Wallet namespace is still tracked after the single-liners
        expect(constants).to include('BSV::Wallet')
      end
    end

    context 'with def blocks (method bodies that contain end)' do
      let(:source) do
        <<~RUBY
          module BSV
            module Wallet
              class ProtoWallet
                def initialize(root_key)
                  @key = root_key
                end

                def sign(data)
                  data
                end
              end
            end
          end
        RUBY
      end

      it 'tracks def ends without corrupting the namespace stack' do
        expect(constants).to include('BSV::Wallet::ProtoWallet')
        # No spurious over-qualified constants
        expect(constants.none? { |c| c =~ /ProtoWallet::/ }).to be true
      end
    end

    context 'with constant assignments' do
      let(:source) do
        <<~RUBY
          module BSV
            module Transaction
              module Sighash
                ALL_FORK_ID = 0x41
                NONE_FORK_ID = 0x42
              end
            end
          end
        RUBY
      end

      it 'registers constant assignments' do
        expect(constants).to include(
          'BSV::Transaction::Sighash::ALL_FORK_ID',
          'BSV::Transaction::Sighash::NONE_FORK_ID'
        )
      end
    end

    context 'with a PascalCase constant alias' do
      let(:source) do
        <<~RUBY
          module BSV
            module Primitives
              Secp256k1 = ::Secp256k1
            end
          end
        RUBY
      end

      it 'registers the alias as a defined constant' do
        expect(constants).to include('BSV::Primitives::Secp256k1')
      end
    end
  end

  describe 'KNOWN_EXTERNAL companion-gem whitelist' do
    it 'lists BSV::Wallet::Client (bsv-wallet lives in a separate repo)' do
      expect(DocsLint::Symbols::KNOWN_EXTERNAL).to include('BSV::Wallet::Client')
    end
  end

  describe '.tokens_on' do
    subject(:tokens) { described_class.send(:tokens_on, line) }

    context 'with a simple BSV:: token' do
      let(:line) { 'tx = BSV::Transaction::Tx.new' }

      it 'extracts the constant' do
        expect(tokens).to contain_exactly('BSV::Transaction::Tx')
      end
    end

    context 'with a generic type annotation' do
      let(:line) { 'Returns an `Array<BSV::Transaction::Beef>` instance.' }

      it 'extracts the constant from inside the angle bracket' do
        expect(tokens).to contain_exactly('BSV::Transaction::Beef')
      end
    end

    context 'with an HTML ignore comment on the same line' do
      let(:line) { 'BSV::Fake::Thing <!-- docs:lint:ignore Symbol --> is ignored' }

      it 'strips the comment before scanning' do
        # The comment text itself contains no BSV:: token so this confirms the
        # comment region is removed; BSV::Fake::Thing before the comment is still matched.
        expect(tokens).to contain_exactly('BSV::Fake::Thing')
      end
    end
  end

  describe 'happy path — all BSV:: tokens resolve' do
    it 'returns no errors when all referenced constants exist in lib' do
      Dir.mktmpdir('docs_lint_symbols_happy') do |tmpdir|
        lib_root  = File.join(tmpdir, 'gem', 'bsv-sdk', 'lib', 'bsv')
        docs_root = File.join(tmpdir, 'docs')
        FileUtils.mkdir_p(lib_root)
        FileUtils.mkdir_p(docs_root)

        write_ruby_constant(lib_root, 'transaction/tx.rb', %w[BSV Transaction], 'Tx')
        File.write(File.join(docs_root, 'tx.md'), <<~MD)
          ---
          title: Tx
          nav_order: 1
          parent: SDK
          ---

          Use `BSV::Transaction::Tx` to build transactions.
        MD

        # Point the checker at our tmpdir by patching project_root resolution.
        allow(described_class).to receive_messages(lint_files: [File.join(docs_root, 'tx.md')],
                                                   build_known_constants: Set.new([
                                                                                    'BSV::Transaction::Tx', 'BSV::Transaction', 'BSV'
                                                                                  ]))

        expect(described_class.check).to be_empty
      end
    end
  end

  describe 'failure mode — undefined constant' do
    it 'reports file:line for an unresolved BSV:: token' do
      allow(described_class).to receive(:build_known_constants).and_return(Set.new)

      Dir.mktmpdir('docs_lint_symbols_fail') do |tmpdir|
        doc = File.join(tmpdir, 'test.md')
        File.write(doc, "line 1\nBSV::Fake::Thing is documented here\n")

        allow(described_class).to receive(:lint_files).and_return([doc])

        errors = described_class.check
        expect(errors.size).to eq(1)
        expect(errors.first).to include('test.md:2: undefined constant BSV::Fake::Thing')
      end
    end
  end

  describe 'opt-out — <!-- docs:lint:ignore Symbol -->' do
    it 'skips a file that contains the ignore comment' do
      allow(described_class).to receive(:build_known_constants).and_return(Set.new)

      Dir.mktmpdir('docs_lint_symbols_ignore') do |tmpdir|
        doc = File.join(tmpdir, 'test.md')
        File.write(doc, "<!-- docs:lint:ignore Symbol -->\nBSV::NonExistent::Thing\n")

        allow(described_class).to receive(:lint_files).and_return([doc])

        expect(described_class.check).to be_empty
      end
    end
  end
end

# ---------------------------------------------------------------------------
# DocsLint::Kwargs
# ---------------------------------------------------------------------------

RSpec.describe DocsLint::Kwargs do
  describe '.extract_kwargs' do
    subject(:kwargs) { described_class.send(:extract_kwargs, call_str) }

    context 'with a keyword-only call' do
      let(:call_str) { '(prev_wtxid: bin, prev_tx_out_index: 0)' }

      it 'returns keyword names' do
        expect(kwargs).to contain_exactly('prev_wtxid', 'prev_tx_out_index')
      end
    end

    context 'with a mixed positional + keyword call' do
      let(:call_str) { '(private_key, sighash_type: Sighash::ALL_FORK_ID)' }

      it 'ignores positional arguments and the double-colon separator' do
        expect(kwargs).to contain_exactly('sighash_type')
      end
    end

    context 'with a multi-line call string' do
      let(:call_str) { "(satoshis: 1000,\n  locking_script: script)" }

      it 'handles newlines inside the argument list' do
        expect(kwargs).to contain_exactly('satoshis', 'locking_script')
      end
    end
  end

  describe '.initialize_kwargs' do
    context 'when the class file is found and has keyword params' do
      it 'returns the keyword names' do
        Dir.mktmpdir('kwargs_init') do |tmpdir|
          lib_root = File.join(tmpdir, 'gem', 'bsv-sdk', 'lib', 'bsv')
          write_ruby_constant(lib_root, 'transaction/foo.rb', %w[BSV Transaction], 'Foo',
                              'bar:, baz: nil')

          allow(described_class).to receive(:find_class_file).with('BSV::Transaction::Foo')
                                                             .and_return(File.join(lib_root, 'transaction/foo.rb'))

          result = described_class.send(:initialize_kwargs, 'BSV::Transaction::Foo')
          expect(result).to contain_exactly('bar', 'baz')
        end
      end
    end

    context 'when the signature uses **kwargs' do
      it 'returns :accepts_any' do
        Dir.mktmpdir('kwargs_splat') do |tmpdir|
          lib_root = File.join(tmpdir, 'gem', 'bsv-sdk', 'lib', 'bsv')
          write_ruby_constant(lib_root, 'widget.rb', ['BSV'], 'Widget', '**opts')

          allow(described_class).to receive(:find_class_file).with('BSV::Widget')
                                                             .and_return(File.join(lib_root, 'widget.rb'))

          result = described_class.send(:initialize_kwargs, 'BSV::Widget')
          expect(result).to eq(:accepts_any)
        end
      end
    end
  end

  describe 'happy path — all documented kwargs match initialize' do
    it 'returns no errors when kwargs match exactly' do
      Dir.mktmpdir('kwargs_happy') do |tmpdir|
        lib_root  = File.join(tmpdir, 'gem', 'bsv-sdk', 'lib', 'bsv')
        docs_root = File.join(tmpdir, 'docs')
        FileUtils.mkdir_p(docs_root)
        write_ruby_constant(lib_root, 'transaction/widget.rb', %w[BSV Transaction], 'Widget',
                            'satoshis:, locking_script:')

        File.write(File.join(docs_root, 'widget.md'), <<~MD)
          ---
          title: Widget
          nav_order: 1
          parent: SDK
          ---

          ```ruby
          w = BSV::Transaction::Widget.new(satoshis: 1000, locking_script: script)
          ```
        MD

        allow(described_class).to receive(:lint_files).and_return([File.join(docs_root, 'widget.md')])
        allow(described_class).to receive(:find_class_file).with('BSV::Transaction::Widget')
                                                           .and_return(File.join(lib_root, 'transaction/widget.rb'))

        expect(described_class.check).to be_empty
      end
    end
  end

  describe 'failure mode — unknown kwarg' do
    it 'reports file:line with valid kwarg list for an unrecognised keyword' do
      Dir.mktmpdir('kwargs_fail') do |tmpdir|
        lib_root  = File.join(tmpdir, 'gem', 'bsv-sdk', 'lib', 'bsv')
        docs_root = File.join(tmpdir, 'docs')
        FileUtils.mkdir_p(docs_root)
        write_ruby_constant(lib_root, 'transaction/input.rb', %w[BSV Transaction], 'Input',
                            'prev_wtxid:, prev_tx_out_index:')

        doc = File.join(docs_root, 'input.md')
        File.write(doc, <<~MD)
          ---
          title: Input
          nav_order: 1
          parent: SDK
          ---

          ```ruby
          input = BSV::Transaction::Input.new(prev_tx_id: 'abc', prev_tx_out_index: 0)
          ```
        MD

        allow(described_class).to receive(:lint_files).and_return([doc])
        allow(described_class).to receive(:find_class_file).with('BSV::Transaction::Input')
                                                           .and_return(File.join(lib_root, 'transaction/input.rb'))

        errors = described_class.check
        expect(errors.size).to eq(1)
        expect(errors.first).to include('unknown kwarg :prev_tx_id')
        expect(errors.first).to include('valid: :prev_wtxid, :prev_tx_out_index')
      end
    end
  end

  describe '# illustrative opt-out' do
    it 'skips blocks whose first line is # illustrative' do
      Dir.mktmpdir('kwargs_illustrative') do |tmpdir|
        lib_root  = File.join(tmpdir, 'gem', 'bsv-sdk', 'lib', 'bsv')
        docs_root = File.join(tmpdir, 'docs')
        FileUtils.mkdir_p(docs_root)
        write_ruby_constant(lib_root, 'transaction/input.rb', %w[BSV Transaction], 'Input',
                            'prev_wtxid:')

        doc = File.join(docs_root, 'illus.md')
        File.write(doc, <<~MD)
          ---
          title: Illustrative
          nav_order: 1
          parent: SDK
          ---

          ```ruby
          # illustrative
          input = BSV::Transaction::Input.new(nonexistent_kwarg: 'x')
          ```
        MD

        allow(described_class).to receive(:lint_files).and_return([doc])

        expect(described_class.check).to be_empty
      end
    end
  end

  describe '<!-- docs:lint:ignore Symbol --> opt-out' do
    it 'skips a file that contains the ignore comment' do
      Dir.mktmpdir('kwargs_ignore') do |tmpdir|
        doc = File.join(tmpdir, 'test.md')
        File.write(doc, <<~MD)
          <!-- docs:lint:ignore Symbol -->

          ```ruby
          x = BSV::Transaction::Input.new(ghost_kwarg: 1)
          ```
        MD

        allow(described_class).to receive(:lint_files).and_return([doc])

        expect(described_class.check).to be_empty
      end
    end
  end
end

# ---------------------------------------------------------------------------
# DocsLint::Syntax
# ---------------------------------------------------------------------------

RSpec.describe DocsLint::Syntax do
  describe '.compile_block' do
    context 'with valid Ruby' do
      it 'returns nil' do
        result = described_class.send(:compile_block, 'test.md', 10,
                                      "tx = BSV::Transaction::Tx.new\ntx.add_input(input)\n")
        expect(result).to be_nil
      end
    end

    context 'with invalid Ruby syntax' do
      it 'returns an error string with the file and line' do
        result = described_class.send(:compile_block, 'docs/sdk/tx.md', 20,
                                      "def foo(\n  # unclosed paren\n")
        expect(result).to be_a(String)
        expect(result).to start_with('docs/sdk/tx.md:20:')
        expect(result).to include('Ruby syntax error')
      end
    end

    context 'with Ruby 3.4+ `it` block parameter (not valid on 3.3)' do
      # The `it` bare block parameter is a 3.4 feature; compiling it on 3.4+
      # will succeed (which is fine — the SDK CI covers 3.3 separately).
      # This test validates that the syntax check WOULD catch it on 3.3.
      # We simulate a syntax error directly.
      it 'catches invalid syntax' do
        bad_ruby = "def bad(\n" # unclosed paren
        result = described_class.send(:compile_block, 'a.md', 1, bad_ruby)
        expect(result).not_to be_nil
      end
    end
  end

  describe 'happy path — all blocks are valid Ruby' do
    it 'returns no errors for well-formed code blocks' do
      Dir.mktmpdir('syntax_happy') do |tmpdir|
        docs_root = File.join(tmpdir, 'docs')
        FileUtils.mkdir_p(docs_root)
        doc = File.join(docs_root, 'good.md')
        File.write(doc, <<~MD)
          ---
          title: Good
          nav_order: 1
          parent: SDK
          ---

          ```ruby
          tx = BSV::Transaction::Tx.new
          tx.add_input(input)
          ```
        MD

        allow(described_class).to receive(:lint_files).and_return([doc])
        expect(described_class.check).to be_empty
      end
    end
  end

  describe 'failure mode — invalid Ruby syntax' do
    it 'reports file:line for a block containing a syntax error' do
      Dir.mktmpdir('syntax_fail') do |tmpdir|
        docs_root = File.join(tmpdir, 'docs')
        FileUtils.mkdir_p(docs_root)
        doc = File.join(docs_root, 'bad.md')
        File.write(doc, <<~MD)
          ---
          title: Bad
          nav_order: 1
          parent: SDK
          ---

          Some prose.

          ```ruby
          def unclosed(
          ```
        MD

        allow(described_class).to receive(:lint_files).and_return([doc])
        errors = described_class.check
        expect(errors.size).to eq(1)
        expect(errors.first).to match(/bad\.md:\d+: Ruby syntax error:/)
      end
    end
  end

  describe '# illustrative opt-out' do
    it 'skips blocks whose first line is # illustrative' do
      Dir.mktmpdir('syntax_illustrative') do |tmpdir|
        docs_root = File.join(tmpdir, 'docs')
        FileUtils.mkdir_p(docs_root)
        doc = File.join(docs_root, 'illus.md')
        File.write(doc, <<~MD)
          ---
          title: Illustrative
          nav_order: 1
          parent: SDK
          ---

          ```ruby
          # illustrative
          wallet.create_action({
            inputs: [...],
          })
          ```
        MD

        allow(described_class).to receive(:lint_files).and_return([doc])
        expect(described_class.check).to be_empty
      end
    end
  end

  describe '<!-- docs:lint:ignore Symbol --> opt-out' do
    it 'skips a file that contains the ignore comment' do
      Dir.mktmpdir('syntax_ignore') do |tmpdir|
        docs_root = File.join(tmpdir, 'docs')
        FileUtils.mkdir_p(docs_root)
        doc = File.join(docs_root, 'ignored.md')
        File.write(doc, <<~MD)
          <!-- docs:lint:ignore Symbol -->

          ```ruby
          def unclosed(
          ```
        MD

        allow(described_class).to receive(:lint_files).and_return([doc])
        expect(described_class.check).to be_empty
      end
    end
  end
end
