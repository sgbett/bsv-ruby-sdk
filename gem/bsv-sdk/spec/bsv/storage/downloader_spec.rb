# frozen_string_literal: true

require 'spec_helper'
require 'bsv-sdk'

# Conformance vector from StorageUtils — used as a real UHRP URL below.
DOWNLOADER_UHRP_URL = 'XUT6PqWb3GP3LR7dmBMCJwZ3oo5g1iGCF3CrpzyuJCemkGu1WGoq'

# Helpers for building real BEEF objects with PushDrop outputs.
module DownloaderSpecHelpers
  def dummy_lock
    BSV::Script::Script.p2pkh_lock(("\x00" * 20).b)
  end

  def pushdrop_script(*fields)
    BSV::Script::Script.pushdrop_lock(fields, dummy_lock)
  end

  def uhrp_output_script(url, expiry)
    url_bytes    = url.encode('UTF-8').b
    expiry_bytes = BSV::Transaction::VarInt.encode(expiry)
    pushdrop_script("\x01".b, "\x02".b, url_bytes, expiry_bytes)
  end

  def beef_with_script(script)
    txout = BSV::Transaction::TransactionOutput.new(satoshis: 1, locking_script: script)
    tx    = BSV::Transaction::Tx.new
    tx.add_output(txout)
    beef = BSV::Transaction::Beef.new
    beef.merge_transaction(tx)
    beef.to_binary
  end

  def output_entry(script)
    { 'beef' => beef_with_script(script), 'outputIndex' => 0 }
  end

  def uhrp_output_entry(url, expiry)
    output_entry(uhrp_output_script(url, expiry))
  end

  def answer_with(outputs)
    BSV::Overlay::LookupAnswer.new(type: 'output-list', outputs: outputs)
  end

  def non_output_list_answer
    BSV::Overlay::LookupAnswer.new(type: 'freeform', outputs: [])
  end
end

# Minimal HTTP response for the injectable http_client lambda.
DownloaderTestResponse = Struct.new(:code, :body, :headers) do
  def [](key)
    headers[key]
  end
end

def http_ok(body, mime_type: 'text/plain')
  DownloaderTestResponse.new(200, body, { 'Content-Type' => mime_type })
end

def http_err(code)
  DownloaderTestResponse.new(code, '', {})
end

RSpec.describe BSV::Storage::Downloader do
  include DownloaderSpecHelpers

  let(:resolver) { instance_double(BSV::Overlay::LookupResolver) }
  let(:downloader) { described_class.new(lookup_resolver: resolver) }

  describe '#resolve' do
    context 'when resolver returns a non-output-list answer' do
      it 'raises DownloadError' do
        allow(resolver).to receive(:query).and_return(non_output_list_answer)
        expect { downloader.resolve(DOWNLOADER_UHRP_URL) }
          .to raise_error(BSV::Storage::DownloadError, 'Lookup answer must be an output list')
      end
    end

    context 'when the caller supplies a uhrp:// prefixed URL' do
      it 'normalises the URL before forwarding to the lookup query' do
        allow(resolver).to receive(:query) do |question|
          # Lookup query should receive the bare base58check form, not the uhrp:// form
          expect(question.query['uhrpUrl']).to eq(DOWNLOADER_UHRP_URL)
          non_output_list_answer
        end
        expect { downloader.resolve("uhrp://#{DOWNLOADER_UHRP_URL}") }
          .to raise_error(BSV::Storage::DownloadError)
      end
    end

    context 'when resolver returns an empty output list' do
      it 'returns an empty array' do
        allow(resolver).to receive(:query).and_return(answer_with([]))
        expect(downloader.resolve(DOWNLOADER_UHRP_URL)).to eq([])
      end
    end

    context 'with a single valid output' do
      it 'returns the URL from field[2]' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query)
          .and_return(answer_with([uhrp_output_entry('http://host1.example/file', future)]))

        expect(downloader.resolve(DOWNLOADER_UHRP_URL)).to eq(['http://host1.example/file'])
      end
    end

    context 'with an expired entry (expiry < now)' do
      it 'drops the expired entry and returns empty' do
        past = Time.now.to_i - 1
        allow(resolver).to receive(:query)
          .and_return(answer_with([uhrp_output_entry('http://expired.example/file', past)]))

        expect(downloader.resolve(DOWNLOADER_UHRP_URL)).to eq([])
      end
    end

    context 'with a mix of valid and expired entries' do
      it 'returns only non-expired URLs' do
        past   = Time.now.to_i - 1
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://expired.example/file', past),
                                                                    uhrp_output_entry('http://valid.example/file', future)
                                                                  ]))

        expect(downloader.resolve(DOWNLOADER_UHRP_URL)).to eq(['http://valid.example/file'])
      end
    end

    context 'with a malformed PushDrop output (fewer than 4 fields)' do
      it 'skips the malformed entry and continues' do
        future      = Time.now.to_i + 3600
        short_entry = output_entry(pushdrop_script("\x01".b, "\x02".b, 'http://short.example'.b))
        valid_entry = uhrp_output_entry('http://valid.example/file', future)
        allow(resolver).to receive(:query).and_return(answer_with([short_entry, valid_entry]))

        expect(downloader.resolve(DOWNLOADER_UHRP_URL)).to eq(['http://valid.example/file'])
      end
    end

    context 'with a BEEF that fails to parse' do
      it 'skips the unparseable entry and continues' do
        future       = Time.now.to_i + 3600
        bad_output   = { 'beef' => 'UNPARSEABLE_BYTES', 'outputIndex' => 0 }
        valid_entry  = uhrp_output_entry('http://good.example/file', future)
        allow(resolver).to receive(:query).and_return(answer_with([bad_output, valid_entry]))

        expect(downloader.resolve(DOWNLOADER_UHRP_URL)).to eq(['http://good.example/file'])
      end
    end

    context 'with a negative outputIndex (untrusted overlay response)' do
      it 'skips the entry rather than reading the wrong output via negative indexing' do
        future        = Time.now.to_i + 3600
        good_entry    = uhrp_output_entry('http://good.example/file', future)
        negative      = good_entry.merge('outputIndex' => -1)
        allow(resolver).to receive(:query).and_return(answer_with([negative, good_entry]))

        expect(downloader.resolve(DOWNLOADER_UHRP_URL)).to eq(['http://good.example/file'])
      end
    end

    context 'with a URL field containing invalid UTF-8 bytes' do
      it 'skips the entry rather than returning an invalid-encoded String' do
        future        = Time.now.to_i + 3600
        # An invalid UTF-8 byte sequence — lone continuation byte 0x80 with no leading byte.
        bad_url_bytes = "\x80\x80\x80".b
        bad_script    = pushdrop_script("\x01".b, "\x02".b, bad_url_bytes, BSV::Transaction::VarInt.encode(future))
        bad_entry     = output_entry(bad_script)
        good_entry    = uhrp_output_entry('http://good.example/file', future)
        allow(resolver).to receive(:query).and_return(answer_with([bad_entry, good_entry]))

        expect(downloader.resolve(DOWNLOADER_UHRP_URL)).to eq(['http://good.example/file'])
      end
    end
  end

  describe '#download' do
    context 'with an invalid UHRP URL' do
      it 'raises ArgumentError' do
        expect { downloader.download('not-a-uhrp-url') }
          .to raise_error(ArgumentError, 'Invalid parameter UHRP url')
      end
    end

    context 'when resolve returns no hosts' do
      it 'raises DownloadError' do
        allow(resolver).to receive(:query).and_return(answer_with([]))
        expect { downloader.download(DOWNLOADER_UHRP_URL) }
          .to raise_error(BSV::Storage::DownloadError, 'No one currently hosts this file!')
      end
    end

    context 'when first host returns 404 and second host returns valid content' do
      let(:content)  { 'hello world content' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'fetches from the second host' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://host1.example/file', future),
                                                                    uhrp_output_entry('http://host2.example/file', future)
                                                                  ]))

        call_count = 0
        http = lambda do |_url|
          call_count += 1
          call_count == 1 ? http_err(404) : http_ok(content, mime_type: 'text/plain')
        end

        result = described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)
        expect(result.data).to eq(content)
        expect(result.mime_type).to eq('text/plain')
        expect(call_count).to eq(2)
      end
    end

    context 'when hash mismatches on every host' do
      let(:content)  { 'real content' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'raises DownloadError' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://bad-host.example/file', future)
                                                                  ]))

        http = ->(_url) { http_ok('wrong content') }
        expect do
          described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)
        end.to raise_error(BSV::Storage::DownloadError, /Unable to download content/)
      end
    end

    context 'when all hosts return 4xx or 5xx' do
      let(:content)  { 'some file' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'raises DownloadError' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://host1.example/file', future),
                                                                    uhrp_output_entry('http://host2.example/file', future)
                                                                  ]))

        http = ->(_url) { http_err(500) }
        expect do
          described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)
        end.to raise_error(BSV::Storage::DownloadError, /Unable to download content/)
      end
    end

    context 'when host returns 302 (redirects are not followed in v1)' do
      let(:content)  { 'redirected content' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'treats 3xx as failed host and tries the next one' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://redirect-host.example/file', future),
                                                                    uhrp_output_entry('http://direct-host.example/file', future)
                                                                  ]))

        call_count = 0
        http = lambda do |_url|
          call_count += 1
          call_count == 1 ? http_err(302) : http_ok(content)
        end

        result = described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)
        expect(result.data).to eq(content)
        expect(call_count).to eq(2)
      end
    end

    context 'when host returns 401 (TS contract: treated as failed host, tries next)' do
      let(:content)  { 'protected content' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'tries the next host and returns successfully' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://auth-host.example/file', future),
                                                                    uhrp_output_entry('http://open-host.example/file', future)
                                                                  ]))

        call_count = 0
        http = lambda do |_url|
          call_count += 1
          call_count == 1 ? http_err(401) : http_ok(content)
        end

        result = described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)
        expect(result.data).to eq(content)
        expect(call_count).to eq(2)
      end
    end

    context 'when host returns 402' do
      let(:content)  { 'paid content' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'treats as failed host and tries next' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://paid-host.example/file', future),
                                                                    uhrp_output_entry('http://free-host.example/file', future)
                                                                  ]))

        call_count = 0
        http = lambda do |_url|
          call_count += 1
          call_count == 1 ? http_err(402) : http_ok(content)
        end

        result = described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)
        expect(result.data).to eq(content)
        expect(call_count).to eq(2)
      end
    end

    context 'when host returns 403' do
      let(:content)  { 'gated content' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'treats as failed host and tries next' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://gated-host.example/file', future),
                                                                    uhrp_output_entry('http://open-host.example/file', future)
                                                                  ]))

        call_count = 0
        http = lambda do |_url|
          call_count += 1
          call_count == 1 ? http_err(403) : http_ok(content)
        end

        result = described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)
        expect(result.data).to eq(content)
        expect(call_count).to eq(2)
      end
    end

    context 'when a network error occurs on a host' do
      let(:content)  { 'network test' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'tries the next host' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://broken-host.example/file', future),
                                                                    uhrp_output_entry('http://working-host.example/file', future)
                                                                  ]))

        call_count = 0
        http = lambda do |_url|
          call_count += 1
          raise Errno::ECONNREFUSED, 'connection refused' if call_count == 1

          http_ok(content)
        end

        result = described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)
        expect(result.data).to eq(content)
        expect(call_count).to eq(2)
      end
    end

    context 'when all hosts raise network errors' do
      let(:content)  { 'unreachable file' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'raises DownloadError' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://dead1.example/file', future),
                                                                    uhrp_output_entry('http://dead2.example/file', future)
                                                                  ]))

        http = ->(_url) { raise SocketError, 'unreachable' }
        expect do
          described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)
        end.to raise_error(BSV::Storage::DownloadError, /Unable to download content/)
      end
    end

    context 'with a successful single-host download' do
      let(:content)  { 'the quick brown fox' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'returns DownloadResult with data and mime_type' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://host.example/file', future)
                                                                  ]))

        http = ->(_url) { http_ok(content, mime_type: 'application/octet-stream') }
        result = described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)

        expect(result).to be_a(BSV::Storage::DownloadResult)
        expect(result.data).to eq(content)
        expect(result.mime_type).to eq('application/octet-stream')
      end
    end

    context 'when the body is empty (treated as failed host)' do
      let(:content)  { 'actual content' }
      let(:uhrp_url) { BSV::Storage::Utils.get_url_for_file(content) }

      it 'tries the next host' do
        future = Time.now.to_i + 3600
        allow(resolver).to receive(:query).and_return(answer_with([
                                                                    uhrp_output_entry('http://empty-host.example/file', future),
                                                                    uhrp_output_entry('http://good-host.example/file', future)
                                                                  ]))

        call_count = 0
        http = lambda do |_url|
          call_count += 1
          call_count == 1 ? DownloaderTestResponse.new(200, '', { 'Content-Type' => 'text/plain' }) : http_ok(content)
        end

        result = described_class.new(lookup_resolver: resolver, http_client: http).download(uhrp_url)
        expect(result.data).to eq(content)
        expect(call_count).to eq(2)
      end
    end
  end
end
