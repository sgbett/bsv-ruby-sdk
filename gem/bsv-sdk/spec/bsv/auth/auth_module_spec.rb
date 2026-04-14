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
      expect(BSV::Auth::ValidateCertificates).to receive(:validate_certificates)
        .with(:wallet, :message, nil)
      BSV::Auth.validate_certificates(:wallet, :message)
    end

    it 'forwards the optional requested_certificates argument' do
      requested = { certifiers: [], types: {} }
      expect(BSV::Auth::ValidateCertificates).to receive(:validate_certificates)
        .with(:wallet, :message, requested)
      BSV::Auth.validate_certificates(:wallet, :message, requested)
    end
  end

  describe 'BSV::Auth.get_verifiable_certificates' do
    it 'is callable and delegates to GetVerifiableCertificates.get_verifiable_certificates' do
      expect(BSV::Auth::GetVerifiableCertificates).to receive(:get_verifiable_certificates)
        .with(:wallet, :requested, :verifier_key)
      BSV::Auth.get_verifiable_certificates(:wallet, :requested, :verifier_key)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
