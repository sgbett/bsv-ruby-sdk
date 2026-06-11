# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'

module BSV
  module Storage
    # Result returned by {Downloader#download}.
    DownloadResult = Data.define(:data, :mime_type)

    # Downloads UHRP-addressed content from distributed storage hosts.
    #
    # Resolution: queries the +ls_uhrp+ lookup service via a {BSV::Overlay::LookupResolver},
    # decodes each PushDrop output to extract the host URL (field[2]) and expiry timestamp
    # (field[3], varint). Expired entries are silently dropped.
    #
    # Download: fetches each resolved URL in turn. Any HTTP 4xx/5xx, empty body, or
    # network exception is treated as a failed host and the next URL is tried. This
    # matches the TS SDK contract — no special treatment of 401/402/403.
    #
    # HTTP redirects are not followed (Net::HTTP default). This is intentional in v1.
    #
    # Download URLs are taken directly from the overlay; no private-IP filter is applied
    # here. (The LookupResolver applies SSRF filtering to SLAP-discovered *infrastructure*
    # hosts — content URLs are end-user data and are not subject to the same filter.)
    class Downloader
      # @param network_preset   [Symbol]                         :mainnet, :testnet, or :local
      # @param lookup_resolver  [BSV::Overlay::LookupResolver]   injectable resolver (nil = default)
      # @param http_client      [#call, nil]                     injectable HTTP client for testing.
      #   Must respond to +.call(url_string)+ and return an object exposing +#code+ (Integer),
      #   +#body+ (binary String), and +#[](header_name)+ for header access.
      #   Default: a thin {Net::HTTP.get_response} wrapper.
      # @param timeout          [Integer]                        per-request timeout in seconds
      def initialize(network_preset: :mainnet, lookup_resolver: nil, http_client: nil, timeout: 30)
        @lookup_resolver = lookup_resolver || BSV::Overlay::LookupResolver.new(network_preset: network_preset)
        @http_client     = http_client
        @timeout         = timeout
      end

      # Resolve a UHRP URL to a list of HTTP(S) download URLs.
      #
      # Queries the +ls_uhrp+ lookup service, decodes each PushDrop output,
      # drops expired entries, and returns the remaining URLs.
      #
      # @param uhrp_url [String] UHRP URL (with or without +uhrp://+ prefix)
      # @return [Array<String>] resolved HTTP(S) download URLs
      # @raise [BSV::Storage::DownloadError] if the lookup answer is not an output-list
      def resolve(uhrp_url)
        question = BSV::Overlay::LookupQuestion.new(
          service: 'ls_uhrp',
          query: { 'uhrpUrl' => uhrp_url }
        )
        answer = @lookup_resolver.query(question)
        raise DownloadError, 'Lookup answer must be an output list' unless answer.type == 'output-list'

        current_time = Time.now.to_i
        urls = []

        answer.outputs.each do |output|
          url = decode_output_url(output, current_time)
          urls << url if url
        end

        urls
      end

      # Download the content addressed by +uhrp_url+.
      #
      # Validates the URL, resolves it to a list of hosts, then attempts each
      # host in order. Verifies the SHA-256 hash of the downloaded body against
      # the hash embedded in the UHRP URL. Returns on the first successful match.
      #
      # @param uhrp_url [String] UHRP URL
      # @return [BSV::Storage::DownloadResult] downloaded data and MIME type
      # @raise [ArgumentError] if the URL is not a valid UHRP URL
      # @raise [BSV::Storage::DownloadError] if no host yields content matching the hash
      def download(uhrp_url)
        raise ArgumentError, 'Invalid parameter UHRP url' unless BSV::Storage::Utils.valid_url?(uhrp_url)

        urls = resolve(uhrp_url)
        raise DownloadError, 'No one currently hosts this file!' if urls.empty?

        expected_hash = BSV::Storage::Utils.get_hash_from_url(uhrp_url)

        urls.each do |url|
          result = attempt_download(url, expected_hash)
          return result if result
        end

        raise DownloadError, "Unable to download content from #{uhrp_url}"
      end

      private

      def decode_output_url(output, current_time)
        beef_data    = output['beef'] || output[:beef]
        output_index = (output['outputIndex'] || output[:output_index] || 0).to_i
        return nil if beef_data.nil?
        return nil if output_index.negative?

        beef   = parse_beef(beef_data)
        return nil unless beef

        beef_tx = beef.transactions.last
        return nil if beef_tx.nil? || beef_tx.is_a?(BSV::Transaction::Beef::TxidOnlyEntry)

        txout = beef_tx.transaction.outputs[output_index]
        return nil unless txout

        fields = txout.locking_script.pushdrop_fields
        return nil if fields.nil? || fields.length < 4

        expiry, = BSV::Transaction::VarInt.decode(fields[3])
        return nil if expiry < current_time

        url = fields[2].force_encoding('UTF-8')
        return nil unless url.valid_encoding?

        url
      rescue StandardError
        nil
      end

      def parse_beef(beef_data)
        case beef_data
        when String
          BSV::Transaction::Beef.from_binary(beef_data)
        when Array
          BSV::Transaction::Beef.from_binary(beef_data.pack('C*'))
        end
      rescue StandardError
        nil
      end

      def attempt_download(url, expected_hash)
        response = fetch(url)
        return nil if response.nil?

        code = response.code.to_i
        return nil if code >= 400

        body = response.body.to_s
        return nil if body.empty?

        actual_hash = OpenSSL::Digest::SHA256.digest(body)
        return nil unless actual_hash == expected_hash

        DownloadResult.new(data: body, mime_type: response['Content-Type'])
      rescue StandardError
        nil
      end

      def fetch(url)
        if @http_client
          @http_client.call(url)
        else
          uri = URI(url)
          Net::HTTP.start(
            uri.hostname,
            uri.port,
            use_ssl: uri.scheme == 'https',
            open_timeout: @timeout,
            read_timeout: @timeout
          ) { |http| http.request(Net::HTTP::Get.new(uri)) }
        end
      rescue StandardError
        nil
      end
    end
  end
end
