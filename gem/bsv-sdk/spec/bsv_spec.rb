# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV do
  it 'has a version number' do
    expect(BSV::VERSION).not_to be_nil
  end
end
