# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'logger'

module BSV
  module Wallet
    # JSON file-backed storage adapter.
    #
    # Persists actions, outputs, and certificates as JSON files in a
    # configurable directory (default: +~/.bsv-wallet/+). Data survives
    # process restarts.
    #
    # Inherits all filtering and pagination logic from {MemoryStore} and
    # adds load-on-init / save-on-mutation.
    #
    # @example Default location
    #   store = BSV::Wallet::FileStore.new
    #   # Data written to ~/.bsv-wallet/
    #
    # @example Custom directory
    #   store = BSV::Wallet::FileStore.new(dir: '/var/lib/my-app/wallet')
    class FileStore < MemoryStore
      DEFAULT_DIR = File.expand_path('~/.bsv-wallet')

      # @param dir [String] directory for JSON files
      #   (default: +~/.bsv-wallet/+ or +BSV_WALLET_DIR+ env var)
      # @param dir [String] directory for JSON files
      # @param logger [Logger, nil] logger for permission warnings (default: Logger to STDERR)
      def initialize(dir: nil, logger: nil)
        super()
        @dir = dir || ENV.fetch('BSV_WALLET_DIR', DEFAULT_DIR)
        @logger = logger || Logger.new($stderr, progname: 'bsv-wallet')
        FileUtils.mkdir_p(@dir, mode: 0o700)
        check_permissions
        load_from_disk
      end

      # @return [String] the storage directory path
      attr_reader :dir

      # --- Mutations: delegate to super, then persist ---

      def store_action(action_data)
        result = super
        save_actions
        result
      end

      def store_output(output_data)
        result = super
        save_outputs
        result
      end

      def delete_output(outpoint)
        result = super
        save_outputs if result
        result
      end

      def update_output_state(outpoint, new_state, pending_reference: nil, no_send: nil)
        result = super
        save_outputs
        result
      end

      def store_certificate(cert_data)
        result = super
        save_certificates
        result
      end

      def delete_certificate(type:, serial_number:, certifier:)
        result = super
        save_certificates if result
        result
      end

      def store_proof(txid, bump_hex)
        super
        save_proofs
      end

      def store_transaction(txid, tx_hex)
        super
        save_transactions
      end

      def store_setting(key, value)
        super
        save_settings
      end

      private

      def proofs_path
        File.join(@dir, 'proofs.json')
      end

      def transactions_path
        File.join(@dir, 'transactions.json')
      end

      def check_permissions
        dir_mode = File.stat(@dir).mode & 0o777
        if dir_mode != 0o700
          @logger.warn("Wallet directory #{@dir} has permissions #{format('%04o', dir_mode)} (expected 0700). " \
                       'Other users may be able to access wallet data.')
        end

        [actions_path, outputs_path, certificates_path, proofs_path, transactions_path, settings_path].each do |path|
          next unless File.exist?(path)

          file_mode = File.stat(path).mode & 0o777
          next if file_mode == 0o600

          @logger.warn("Wallet file #{path} has permissions #{format('%04o', file_mode)} (expected 0600). " \
                       'Other users may be able to read wallet data.')
        end
      end

      def actions_path
        File.join(@dir, 'actions.json')
      end

      def settings_path
        File.join(@dir, 'settings.json')
      end

      def outputs_path
        File.join(@dir, 'outputs.json')
      end

      def certificates_path
        File.join(@dir, 'certificates.json')
      end

      def load_from_disk
        @actions = load_file(actions_path)
        @outputs = load_file(outputs_path)
        @certificates = load_file(certificates_path)
        @proofs = load_proofs_file
        @transactions = load_transactions_file
        @settings = load_settings_file
      end

      def load_file(path)
        return [] unless File.exist?(path)

        data = JSON.parse(File.read(path))
        return [] unless data.is_a?(Array)

        # Symbolise top-level keys for consistency with MemoryStore
        data.map { |entry| symbolise_keys(entry) }
      rescue JSON::ParserError
        []
      end

      def save_actions
        write_file(actions_path, @actions)
      end

      def save_outputs
        write_file(outputs_path, @outputs)
      end

      def save_certificates
        write_file(certificates_path, @certificates)
      end

      def save_proofs
        json = JSON.pretty_generate(@proofs)
        tmp = "#{proofs_path}.tmp"
        File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(json) }
        File.rename(tmp, proofs_path)
      end

      def load_proofs_file
        return {} unless File.exist?(proofs_path)

        data = JSON.parse(File.read(proofs_path))
        data.is_a?(Hash) ? data : {}
      rescue JSON::ParserError
        {}
      end

      def save_transactions
        json = JSON.pretty_generate(@transactions)
        tmp = "#{transactions_path}.tmp"
        File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(json) }
        File.rename(tmp, transactions_path)
      end

      def load_transactions_file
        return {} unless File.exist?(transactions_path)

        data = JSON.parse(File.read(transactions_path))
        data.is_a?(Hash) ? data : {}
      rescue JSON::ParserError
        {}
      end

      def save_settings
        json = JSON.pretty_generate(stringify_keys_deep(@settings))
        tmp = "#{settings_path}.tmp"
        File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(json) }
        File.rename(tmp, settings_path)
      end

      def load_settings_file
        return {} unless File.exist?(settings_path)

        data = JSON.parse(File.read(settings_path))
        data.is_a?(Hash) ? data : {}
      rescue JSON::ParserError
        {}
      end

      def write_file(path, data)
        json = JSON.pretty_generate(stringify_keys_deep(data))
        tmp = "#{path}.tmp"
        File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(json) }
        File.rename(tmp, path)
      end

      def symbolise_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(k, v), result|
          result[k.to_sym] = case v
                             when Hash then symbolise_keys(v)
                             when Array then v.map { |e| e.is_a?(Hash) ? symbolise_keys(e) : e }
                             else v
                             end
        end
      end

      def stringify_keys_deep(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), result|
            result[k.to_s] = stringify_keys_deep(v)
          end
        when Array
          obj.map { |e| stringify_keys_deep(e) }
        else
          obj
        end
      end
    end
  end
end
