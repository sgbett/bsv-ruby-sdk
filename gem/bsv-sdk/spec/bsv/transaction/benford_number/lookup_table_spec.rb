# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::Transaction do
  describe '#benford_number(min, max)' do
    def ts_sdk_reference_benford_number_scaler(min, max, rnd)
      # from: src/transaction/Transaction.ts private benfordNumber (min: number, max: number): number
      (min + (((max - min) * Math.log10(1 + (1.0 / rnd))) / Math.log10(10))).floor
    end

    subject { tx.send(:benford_number, min, max) }

    let(:tx) { described_class.allocate }

    let(:min) { 1 }
    let(:max) { 21_000_000_000_000_000 } # 21m Bitcoin = 2100 * 1m * 1m satoshis

    before { allow(Random).to receive(:rand).and_return(rnd - 1) } # index starts at 0

    (1..9).to_a.each do |r|
      context "when rnd is #{r}" do
        let(:rnd) { r }

        it { is_expected.to eq ts_sdk_reference_benford_number_scaler(min, max, rnd) }
      end
    end

    #     # Make sure it works for a variety of numbers
    #
    #     require 'prime'
    #
    #     # up to 21q sats / 21m Bitcoin
    #     big_numbers = Prime.take_while {|p| p < 100_000}.collect{|n| n * 210_018_901_701 }
    #     # max = 20_999_999_999_984_691 =>  21q sats ( 21m Bitcoin)
    #     # min =        420_037_803_402 => 420b sats (420k Bitcoin)
    #
    #     # up to 420b sats / 420k Bitcoin
    #     medium_numbers = Prime.take_while {|p| p < 10_000}.collect{|n| n * 42_113_707 }
    #     # max = 419_999_999_911 => 420b sats ( 420k Bitcoin)
    #     # min =      84_227_414 => 8.4m sats ( 0.08 Bitcoin)
    #
    #     # up to 8.4m Sats / 0.084 Bitcoin
    #     small_numbers = Prime.take_while {|p| p < 1000}.collect{|n| n * 8425 }
    #     # max = 8_399_725 =>   8.4m sats (0.084 Bitcoin)
    #     # min =    16_850 => 16,850 sats (0.084 Bitcoin)
    #
    #     (1..9).to_a.each do |r|
    #       context "when rnd if #{r}" do
    #
    #         let(:rnd) { r }
    #
    #         it { is_expected.to eq ts_sdk_reference_benford_number_scaler(min,max,rnd) }
    #
    #         big_numbers.each do |number|
    #           context "when max is #{number}" do
    #             let(:max) { number }
    #             it { is_expected.to eq ts_sdk_reference_benford_number_scaler(min,max,rnd) }
    #           end
    #         end
    #
    #         medium_numbers.each do |number|
    #           context "when max is #{number}" do
    #             let(:max) { number }
    #
    #             it { is_expected.to eq ts_sdk_reference_benford_number_scaler(min,max,rnd) }
    #           end
    #         end
    #
    #         small_numbers.each do |number|
    #           context "when max is #{number}" do
    #             let(:max) { number }
    #
    #             it { is_expected.to eq ts_sdk_reference_benford_number_scaler(min,max,rnd) }
    #           end
    #         end
    #       end
    #     end
  end
end
