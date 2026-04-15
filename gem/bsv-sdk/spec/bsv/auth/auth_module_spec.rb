# frozen_string_literal: true

require 'spec_helper'

# Smoke tests for BSV::Auth module-level delegation to certificate utility modules.
#
# Verifies:
# - Autoload resolves BSV::Auth::ValidateCertificates
# - Autoload resolves BSV::Auth::GetVerifiableCertificates
# - BSV::Auth.validate_certificates delegates correctly
# - BSV::Auth.get_verifiable_certificates delegates correctly

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Auth module delegation' do
  describe 'autoload resolution' do
    it 'resolves BSV::Auth::ValidateCertificates without errors' do
      expect { BSV::Auth::ValidateCertificates }.not_to raise_error
    end

    it 'resolves BSV::Auth::GetVerifiableCertificates without errors' do
      expect { BSV::Auth::GetVerifiableCertificates }.not_to raise_error
    end
  end

  describe 'BSV::Auth.validate_certificates' do
    it 'is callable and delegates to ValidateCertificates.validate_certificates' do
      allow(BSV::Auth::ValidateCertificates).to receive(:validate_certificates)
      BSV::Auth.validate_certificates(:wallet, :message)
      expect(BSV::Auth::ValidateCertificates).to have_received(:validate_certificates)
        .with(:wallet, :message, nil)
    end

    it 'forwards the optional requested_certificates argument' do
      requested = { certifiers: [], types: {} }
      allow(BSV::Auth::ValidateCertificates).to receive(:validate_certificates)
      BSV::Auth.validate_certificates(:wallet, :message, requested)
      expect(BSV::Auth::ValidateCertificates).to have_received(:validate_certificates)
        .with(:wallet, :message, requested)
    end
  end

  describe 'BSV::Auth.get_verifiable_certificates' do
    it 'is callable and delegates to GetVerifiableCertificates.get_verifiable_certificates' do
      allow(BSV::Auth::GetVerifiableCertificates).to receive(:get_verifiable_certificates)
      BSV::Auth.get_verifiable_certificates(:wallet, :requested, :verifier_key)
      expect(BSV::Auth::GetVerifiableCertificates).to have_received(:get_verifiable_certificates)
        .with(:wallet, :requested, :verifier_key)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
