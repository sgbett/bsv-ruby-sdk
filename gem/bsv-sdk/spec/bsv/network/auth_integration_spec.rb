# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass

require 'spec_helper'

# Minimal fake HTTP response — mimics Net::HTTPResponse.
AuthIntegrationFakeResponse = Struct.new(:code, :body)

# Injectable HTTP client that records the last request, returns a canned response.
# Used to inspect auth headers set by the full factory → Provider → Protocol stack.
class AuthIntegrationFakeHttpClient
  attr_reader :last_request

  def initialize(response)
    @response = response
  end

  def request(_uri, req)
    @last_request = req
    @response
  end
end

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Builds a fake HTTP client that returns a minimal successful ARC JSON response
# and records the request for header inspection.
def arc_fake_http
  body = '{"txid":"deadbeef","txStatus":"MINED"}'
  AuthIntegrationFakeHttpClient.new(AuthIntegrationFakeResponse.new('200', body))
end

# Builds a fake HTTP client that returns a minimal successful WoC broadcast response.
def woc_fake_http
  AuthIntegrationFakeHttpClient.new(AuthIntegrationFakeResponse.new('200', 'ok'))
end

# Builds a fake HTTP client returning a minimal TAAL binary broadcast response.
def taal_binary_fake_http
  body = '{"txid":"cafebeef"}'
  AuthIntegrationFakeHttpClient.new(AuthIntegrationFakeResponse.new('200', body))
end

# Minimal transaction double that satisfies ARC's escape-hatch broadcast.
def dummy_tx
  tx = double('tx') # rubocop:disable RSpec/VerifiedDoubles
  allow(tx).to receive_messages(to_ef_hex: 'deadbeef', to_binary: "\xde\xad")
  allow(tx).to receive(:respond_to?).and_return(false)
  allow(tx).to receive(:respond_to?).with(:to_binary).and_return(true)
  tx
end

# ---------------------------------------------------------------------------
# Integration specs
# ---------------------------------------------------------------------------

RSpec.describe 'Provider auth mechanisms — end-to-end integration' do
  # ── Scenario 1: WoC with auth: { api_key: } ─────────────────────────────────
  #
  # WoCREST sends the raw key with no Bearer prefix (WoC style).

  describe 'WhatsOnChain with auth: { api_key: }' do
    let(:woc_provider) do
      BSV::Network::Providers::WhatsOnChain.mainnet(
        auth: { api_key: 'woc-secret' },
        http_client: woc_fake_http
      )
    end

    it 'provider.auth is the api_key hash' do
      expect(woc_provider.auth).to eq({ api_key: 'woc-secret' })
    end

    it 'provider.authenticated? is true' do
      expect(woc_provider.authenticated?).to be(true)
    end

    it 'protocol receives auth: { api_key: }' do
      expect(woc_provider.protocols[0].auth).to eq({ api_key: 'woc-secret' })
    end

    it 'HTTP request has Authorization: woc-secret (no Bearer prefix)' do
      # Trigger a broadcast call so the HTTP client records the request.
      # WoCREST broadcast sends the raw tx hex in the body.
      http = woc_fake_http
      p = BSV::Network::Providers::WhatsOnChain.mainnet(
        auth: { api_key: 'woc-secret' },
        http_client: http
      )
      p.call(:broadcast, body: 'rawhex')
      expect(http.last_request['Authorization']).to eq('woc-secret')
    end

    it 'Authorization header does not include Bearer prefix' do
      http = woc_fake_http
      p = BSV::Network::Providers::WhatsOnChain.mainnet(
        auth: { api_key: 'woc-secret' },
        http_client: http
      )
      p.call(:broadcast, body: 'rawhex')
      expect(http.last_request['Authorization']).not_to start_with('Bearer')
    end
  end

  # ── Scenario 2: GorillaPool ARC with auth: { bearer: } ─────────────────────
  #
  # GorillaPool ARC uses Bearer token auth.

  describe 'GorillaPool with auth: { bearer: }' do
    it 'provider.auth is the bearer hash' do
      p = BSV::Network::Providers::GorillaPool.mainnet(
        auth: { bearer: 'gp-bearer-token' },
        http_client: arc_fake_http
      )
      expect(p.auth).to eq({ bearer: 'gp-bearer-token' })
    end

    it 'provider.authenticated? is true' do
      p = BSV::Network::Providers::GorillaPool.mainnet(
        auth: { bearer: 'gp-bearer-token' },
        http_client: arc_fake_http
      )
      expect(p.authenticated?).to be(true)
    end

    it 'ARC protocol receives auth: { bearer: }' do
      p = BSV::Network::Providers::GorillaPool.mainnet(
        auth: { bearer: 'gp-bearer-token' },
        http_client: arc_fake_http
      )
      arc = p.protocols.find { |pr| pr.is_a?(BSV::Network::Protocols::ARC) }
      expect(arc.auth).to eq({ bearer: 'gp-bearer-token' })
    end

    it 'HTTP request has Authorization: Bearer gp-bearer-token' do
      http = arc_fake_http
      p = BSV::Network::Providers::GorillaPool.mainnet(
        auth: { bearer: 'gp-bearer-token' },
        http_client: http
      )
      tx = dummy_tx
      p.call(:broadcast, tx)
      expect(http.last_request['Authorization']).to eq('Bearer gp-bearer-token')
    end
  end

  # ── Scenario 3: GorillaPool ARC with custom header auth ─────────────────────
  #
  # Custom header: auth: { api_key: 'key', header: 'Api-Key' } → Api-Key: key

  describe 'GorillaPool with auth: { api_key:, header: }' do
    it 'HTTP request has Api-Key: key header' do
      http = arc_fake_http
      p = BSV::Network::Providers::GorillaPool.mainnet(
        auth: { api_key: 'gp-key', header: 'Api-Key' },
        http_client: http
      )
      tx = dummy_tx
      p.call(:broadcast, tx)
      expect(http.last_request['Api-Key']).to eq('gp-key')
    end

    it 'Authorization header is absent when custom header is used' do
      http = arc_fake_http
      p = BSV::Network::Providers::GorillaPool.mainnet(
        auth: { api_key: 'gp-key', header: 'Api-Key' },
        http_client: http
      )
      tx = dummy_tx
      p.call(:broadcast, tx)
      expect(http.last_request['Authorization']).to be_nil
    end
  end

  # ── Scenario 4: TAAL ARC with auth: { bearer: } ─────────────────────────────
  #
  # TAAL ARC broadcast uses Bearer token via ARC (first-registered wins).

  describe 'TAAL with auth: { bearer: }' do
    it 'provider.auth is the bearer hash' do
      p = BSV::Network::Providers::TAAL.mainnet(
        auth: { bearer: 'taal-bearer-token' },
        http_client: arc_fake_http
      )
      expect(p.auth).to eq({ bearer: 'taal-bearer-token' })
    end

    it 'HTTP request has Authorization: Bearer taal-bearer-token' do
      http = arc_fake_http
      p = BSV::Network::Providers::TAAL.mainnet(
        auth: { bearer: 'taal-bearer-token' },
        http_client: http
      )
      tx = dummy_tx
      p.call(:broadcast, tx)
      expect(http.last_request['Authorization']).to eq('Bearer taal-bearer-token')
    end
  end

  # ── Scenario 5: TAALBinary with auth: { api_key: } (escape hatch) ───────────
  #
  # TAALBinary translates api_key: to auth: { api_key: } (no Bearer prefix)
  # and sets the raw key on the Authorization header.

  describe 'TAALBinary with auth: { api_key: }' do
    it 'Authorization header has raw key (no Bearer)' do
      http = taal_binary_fake_http
      tb = BSV::Network::Protocols::TAALBinary.new(
        base_url: 'https://api.taal.com',
        auth: { api_key: 'mainnet_rawkey' },
        http_client: http
      )
      tb.call(:broadcast, "\x00")
      expect(http.last_request['Authorization']).to eq('mainnet_rawkey')
    end

    it 'Authorization header has no Bearer prefix' do
      http = taal_binary_fake_http
      tb = BSV::Network::Protocols::TAALBinary.new(
        base_url: 'https://api.taal.com',
        auth: { api_key: 'mainnet_rawkey' },
        http_client: http
      )
      tb.call(:broadcast, "\x00")
      expect(http.last_request['Authorization']).not_to start_with('Bearer')
    end
  end

  # ── Scenario 6: Unauthenticated provider ────────────────────────────────────
  #
  # No auth kwargs → auth: :none → no Authorization header on any request.

  describe 'unauthenticated provider (no auth supplied)' do
    it 'GorillaPool provider.auth is :none' do
      p = BSV::Network::Providers::GorillaPool.mainnet(http_client: arc_fake_http)
      expect(p.auth).to eq(:none)
    end

    it 'GorillaPool provider.authenticated? is false' do
      p = BSV::Network::Providers::GorillaPool.mainnet(http_client: arc_fake_http)
      expect(p.authenticated?).to be(false)
    end

    it 'GorillaPool HTTP request has no Authorization header' do
      http = arc_fake_http
      p = BSV::Network::Providers::GorillaPool.mainnet(http_client: http)
      tx = dummy_tx
      p.call(:broadcast, tx)
      expect(http.last_request['Authorization']).to be_nil
    end

    it 'WhatsOnChain provider.auth is :none' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(http_client: woc_fake_http)
      expect(p.auth).to eq(:none)
    end

    it 'WhatsOnChain HTTP request has no Authorization header' do
      http = woc_fake_http
      p = BSV::Network::Providers::WhatsOnChain.mainnet(http_client: http)
      p.call(:broadcast, body: 'rawhex')
      expect(http.last_request['Authorization']).to be_nil
    end

    it 'TAAL provider.auth is :none' do
      p = BSV::Network::Providers::TAAL.mainnet(http_client: arc_fake_http)
      expect(p.auth).to eq(:none)
    end
  end

  # ── Scenario 7: Provider metadata readback ──────────────────────────────────
  #
  # Verify auth, rate_limit, and authenticated? surface the correct values
  # from each factory.

  describe 'provider metadata readback' do
    describe 'WhatsOnChain' do
      it 'provider.rate_limit defaults to DEFAULT_RATE_LIMIT' do
        p = BSV::Network::Providers::WhatsOnChain.mainnet(http_client: woc_fake_http)
        expect(p.rate_limit).to eq(BSV::Network::Providers::WhatsOnChain::DEFAULT_RATE_LIMIT)
      end

      it 'provider.rate_limit reflects supplied rate_limit' do
        p = BSV::Network::Providers::WhatsOnChain.mainnet(rate_limit: 20, http_client: woc_fake_http)
        expect(p.rate_limit).to eq(20)
      end

      it 'provider.authenticated? is false with no auth' do
        p = BSV::Network::Providers::WhatsOnChain.mainnet(http_client: woc_fake_http)
        expect(p.authenticated?).to be(false)
      end

      it 'provider.authenticated? is true with auth: hash' do
        p = BSV::Network::Providers::WhatsOnChain.mainnet(auth: { api_key: 'k' }, http_client: woc_fake_http)
        expect(p.authenticated?).to be(true)
      end
    end

    describe 'GorillaPool' do
      it 'provider.rate_limit defaults to DEFAULT_RATE_LIMIT' do
        p = BSV::Network::Providers::GorillaPool.mainnet(http_client: arc_fake_http)
        expect(p.rate_limit).to eq(BSV::Network::Providers::GorillaPool::DEFAULT_RATE_LIMIT)
      end

      it 'provider.rate_limit reflects supplied rate_limit' do
        p = BSV::Network::Providers::GorillaPool.mainnet(rate_limit: 50, http_client: arc_fake_http)
        expect(p.rate_limit).to eq(50)
      end

      it 'provider.authenticated? is true with bearer auth' do
        p = BSV::Network::Providers::GorillaPool.mainnet(auth: { bearer: 'tok' }, http_client: arc_fake_http)
        expect(p.authenticated?).to be(true)
      end
    end

    describe 'TAAL' do
      it 'provider.rate_limit is nil by default' do
        p = BSV::Network::Providers::TAAL.mainnet(http_client: arc_fake_http)
        expect(p.rate_limit).to be_nil
      end

      it 'provider.rate_limit reflects supplied rate_limit' do
        p = BSV::Network::Providers::TAAL.mainnet(rate_limit: 25, http_client: arc_fake_http)
        expect(p.rate_limit).to eq(25)
      end

      it 'provider.authenticated? is true with api_key auth' do
        p = BSV::Network::Providers::TAAL.mainnet(auth: { api_key: 'taal-k' }, http_client: arc_fake_http)
        expect(p.authenticated?).to be(true)
      end
    end
  end

  # ── Scenario 8: Legacy api_key: path end-to-end ─────────────────────────────
  #
  # Legacy api_key: kwarg still works through the full factory → protocol →
  # HTTP request stack. Each factory translates it differently:
  # - WoC: api_key: → auth: { api_key: } → Authorization: key (no Bearer)
  # - GorillaPool: api_key: → auth: { bearer: } → Authorization: Bearer key
  # - TAAL ARC: api_key: → legacy path → Authorization: Bearer key
  # - TAAL TAALBinary: api_key: → auth: { api_key: } → Authorization: key

  describe 'legacy api_key: path' do
    it 'WhatsOnChain — HTTP request has Authorization: key (no Bearer)' do
      http = woc_fake_http
      p = BSV::Network::Providers::WhatsOnChain.mainnet(api_key: 'legacy-woc-key', http_client: http)
      p.call(:broadcast, body: 'rawhex')
      expect(http.last_request['Authorization']).to eq('legacy-woc-key')
    end

    it 'WhatsOnChain — provider.authenticated? is true' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(api_key: 'legacy-woc-key', http_client: woc_fake_http)
      expect(p.authenticated?).to be(true)
    end

    it 'GorillaPool — HTTP request has Authorization: Bearer key' do
      http = arc_fake_http
      p = BSV::Network::Providers::GorillaPool.mainnet(api_key: 'legacy-gp-key', http_client: http)
      tx = dummy_tx
      p.call(:broadcast, tx)
      expect(http.last_request['Authorization']).to eq('Bearer legacy-gp-key')
    end

    it 'GorillaPool — provider.authenticated? is true' do
      p = BSV::Network::Providers::GorillaPool.mainnet(api_key: 'legacy-gp-key', http_client: arc_fake_http)
      expect(p.authenticated?).to be(true)
    end

    it 'TAAL ARC — HTTP request has Authorization: Bearer key' do
      http = arc_fake_http
      p = BSV::Network::Providers::TAAL.mainnet(api_key: 'legacy-taal-key', http_client: http)
      tx = dummy_tx
      p.call(:broadcast, tx)
      expect(http.last_request['Authorization']).to eq('Bearer legacy-taal-key')
    end

    it 'TAAL — provider.authenticated? is true' do
      p = BSV::Network::Providers::TAAL.mainnet(api_key: 'legacy-taal-key', http_client: arc_fake_http)
      expect(p.authenticated?).to be(true)
    end
  end

  # ── Edge cases ───────────────────────────────────────────────────────────────

  describe 'edge cases' do
    it 'auth: nil is normalised to :none on provider' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(auth: nil, http_client: woc_fake_http)
      expect(p.auth).to eq(:none)
    end

    it 'auth: {} is normalised to :none on provider' do
      p = BSV::Network::Providers::WhatsOnChain.mainnet(auth: {}, http_client: woc_fake_http)
      expect(p.auth).to eq(:none)
    end

    it 'auth: nil — provider.authenticated? is false' do
      p = BSV::Network::Providers::GorillaPool.mainnet(auth: nil, http_client: arc_fake_http)
      expect(p.authenticated?).to be(false)
    end

    it 'auth: {} — provider.authenticated? is false' do
      p = BSV::Network::Providers::GorillaPool.mainnet(auth: {}, http_client: arc_fake_http)
      expect(p.authenticated?).to be(false)
    end

    it 'auth: nil — no Authorization header in HTTP request' do
      http = arc_fake_http
      p = BSV::Network::Providers::GorillaPool.mainnet(auth: nil, http_client: http)
      tx = dummy_tx
      p.call(:broadcast, tx)
      expect(http.last_request['Authorization']).to be_nil
    end

    it 'auth: {} — no Authorization header in HTTP request' do
      http = arc_fake_http
      p = BSV::Network::Providers::GorillaPool.mainnet(auth: {}, http_client: http)
      tx = dummy_tx
      p.call(:broadcast, tx)
      expect(http.last_request['Authorization']).to be_nil
    end

    it 'auth: takes precedence over api_key: in WhatsOnChain' do
      http = woc_fake_http
      p = BSV::Network::Providers::WhatsOnChain.mainnet(
        auth: { api_key: 'explicit-key' },
        api_key: 'legacy-key',
        http_client: http
      )
      p.call(:broadcast, body: 'rawhex')
      expect(http.last_request['Authorization']).to eq('explicit-key')
    end
  end
end

# rubocop:enable RSpec/DescribeClass
