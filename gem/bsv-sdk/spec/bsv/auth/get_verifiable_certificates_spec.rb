# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Auth.get_verifiable_certificates' do
  # rubocop:enable RSpec/DescribeClass

  let(:verifier_key) { "02#{'ab' * 32}" }

  let(:cert_type_a) { 'dHlwZUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE=' }
  let(:cert_type_b) { 'dHlwZUJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI=' }

  let(:serial_a) { 'c2VyaWFsQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE=' }
  let(:serial_b) { 'c2VyaWFsQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI=' }

  let(:subject_key) { "03#{'cd' * 32}" }
  let(:certifier_a) { "02#{'11' * 32}" }
  let(:outpoint)    { "#{'aa' * 32}.0" }

  let(:cert_hash_a) do
    {
      type: cert_type_a,
      serial_number: serial_a,
      subject: subject_key,
      certifier: certifier_a,
      revocation_outpoint: outpoint,
      fields: { 'name' => 'ZW5jcnlwdGVk' },
      signature: nil
    }
  end

  let(:cert_hash_b) do
    {
      type: cert_type_b,
      serial_number: serial_b,
      subject: subject_key,
      certifier: certifier_a,
      revocation_outpoint: outpoint,
      fields: { 'email' => 'ZW5jcnlwdGVkMg==' },
      signature: nil
    }
  end

  let(:keyring_a) { { 'name' => 'a2V5cmluZ0FBQQ==' } }
  let(:keyring_b) { { 'email' => 'a2V5cmluZ0JCQg==' } }

  let(:requested_certificates) do
    {
      certifiers: [certifier_a],
      types: {
        cert_type_a => ['name'],
        cert_type_b => ['email']
      }
    }
  end

  context 'when wallet does not respond to list_certificates' do
    it 'returns []' do
      wallet = double('wallet') # rubocop:disable RSpec/VerifiedDoubles
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(false)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(true)

      result = BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      expect(result).to eq([])
    end
  end

  context 'when wallet does not respond to prove_certificate' do
    it 'returns []' do
      wallet = double('wallet') # rubocop:disable RSpec/VerifiedDoubles
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(true)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(false)

      result = BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      expect(result).to eq([])
    end
  end

  context 'when list_certificates returns empty results' do
    it 'returns []' do
      wallet = double('wallet') # rubocop:disable RSpec/VerifiedDoubles
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(true)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(true)
      allow(wallet).to receive(:list_certificates).and_return({ certificates: [] })

      result = BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      expect(result).to eq([])
    end
  end

  context 'when wallet returns a single matching certificate' do
    let(:wallet) { double('wallet') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(true)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(true)
      allow(wallet).to receive_messages(list_certificates: { certificates: [cert_hash_a] }, prove_certificate: { keyring_for_verifier: keyring_a })
    end

    it 'returns an array with one VerifiableCertificate' do
      result = BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      expect(result.length).to eq(1)
      expect(result.first).to be_a(BSV::Auth::VerifiableCertificate)
    end

    it 'passes the correct fields_to_reveal to prove_certificate' do
      BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)

      expect(wallet).to have_received(:prove_certificate).with(
        certificate: cert_hash_a,
        fields_to_reveal: ['name'],
        verifier: verifier_key
      )
    end

    it 'assigns the keyring from prove_certificate to the VerifiableCertificate' do
      result = BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      expect(result.first.keyring).to eq(keyring_a)
    end

    it 'preserves certificate attributes' do
      result = BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      cert = result.first
      expect(cert.type).to eq(cert_type_a)
      expect(cert.serial_number).to eq(serial_a)
      expect(cert.subject).to eq(subject_key)
      expect(cert.certifier).to eq(certifier_a)
    end
  end

  context 'when wallet returns multiple matching certificates' do
    let(:wallet) { double('wallet') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(true)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(true)
      allow(wallet).to receive(:list_certificates).and_return({ certificates: [cert_hash_a, cert_hash_b] })
      allow(wallet).to receive(:prove_certificate).with(hash_including(certificate: cert_hash_a)).and_return({ keyring_for_verifier: keyring_a })
      allow(wallet).to receive(:prove_certificate).with(hash_including(certificate: cert_hash_b)).and_return({ keyring_for_verifier: keyring_b })
    end

    it 'returns an array with two VerifiableCertificates' do
      result = BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      expect(result.length).to eq(2)
      expect(result).to all(be_a(BSV::Auth::VerifiableCertificate))
    end

    it 'assigns the correct keyring to each certificate' do
      result = BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      expect(result[0].keyring).to eq(keyring_a)
      expect(result[1].keyring).to eq(keyring_b)
    end
  end

  context 'when prove_certificate raises UnsupportedActionError' do
    let(:wallet) { double('wallet') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(true)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(true)
      allow(wallet).to receive(:list_certificates).and_return({ certificates: [cert_hash_a] })
      allow(wallet).to receive(:prove_certificate).and_raise(BSV::Wallet::UnsupportedActionError)
    end

    it 'returns []' do
      result = BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      expect(result).to eq([])
    end
  end

  context 'when list_certificates raises UnsupportedActionError' do
    let(:wallet) { double('wallet') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(true)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(true)
      allow(wallet).to receive(:list_certificates).and_raise(BSV::Wallet::UnsupportedActionError)
    end

    it 'returns []' do
      result = BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      expect(result).to eq([])
    end
  end

  context 'when prove_certificate raises an unexpected error' do
    let(:wallet) { double('wallet') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(true)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(true)
      allow(wallet).to receive(:list_certificates).and_return({ certificates: [cert_hash_a] })
      allow(wallet).to receive(:prove_certificate).and_raise(RuntimeError, 'protocol mismatch')
    end

    it 'propagates the error to the caller' do
      expect do
        BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      end.to raise_error(RuntimeError, 'protocol mismatch')
    end
  end

  context 'when list_certificates raises an unexpected error' do
    let(:wallet) { double('wallet') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(true)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(true)
      allow(wallet).to receive(:list_certificates).and_raise(RuntimeError, 'network error')
    end

    it 'propagates the error to the caller' do
      expect do
        BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      end.to raise_error(RuntimeError, 'network error')
    end
  end

  context 'when prove_certificate raises ArgumentError' do
    let(:wallet) { double('wallet') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(true)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(true)
      allow(wallet).to receive(:list_certificates).and_return({ certificates: [cert_hash_a] })
      allow(wallet).to receive(:prove_certificate).and_raise(ArgumentError, 'invalid verifier key')
    end

    it 'propagates the error to the caller' do
      expect do
        BSV::Auth.get_verifiable_certificates(wallet, requested_certificates, verifier_key)
      end.to raise_error(ArgumentError, 'invalid verifier key')
    end
  end

  context 'when requested_certificates uses string keys' do
    let(:wallet) { double('wallet') } # rubocop:disable RSpec/VerifiedDoubles

    let(:requested_with_string_keys) do
      {
        'certifiers' => [certifier_a],
        'types' => { cert_type_a => ['name'] }
      }
    end

    before do
      allow(wallet).to receive(:respond_to?).with(:list_certificates).and_return(true)
      allow(wallet).to receive(:respond_to?).with(:prove_certificate).and_return(true)
      allow(wallet).to receive_messages(list_certificates: { certificates: [cert_hash_a] }, prove_certificate: { keyring_for_verifier: keyring_a })
    end

    it 'handles string-keyed requested_certificates correctly' do
      result = BSV::Auth.get_verifiable_certificates(wallet, requested_with_string_keys, verifier_key)
      expect(result.length).to eq(1)
      expect(result.first).to be_a(BSV::Auth::VerifiableCertificate)
    end
  end
end
