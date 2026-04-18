# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::Specifier do
  describe '#initialize' do
    it 'raises ArgumentError when only: and except: are both provided' do
      expect { described_class.new(only: [:broadcast], except: [:get_tx]) }
        .to raise_error(ArgumentError, /at most one/)
    end

    it 'raises ArgumentError when only: and filter: are both provided' do
      expect { described_class.new(only: [:broadcast], filter: ->(_cmd) { true }) }
        .to raise_error(ArgumentError, /at most one/)
    end

    it 'raises ArgumentError when except: and filter: are both provided' do
      expect { described_class.new(except: [:broadcast], filter: ->(_cmd) { true }) }
        .to raise_error(ArgumentError, /at most one/)
    end

    it 'raises ArgumentError when all three options are provided' do
      expect { described_class.new(only: [:broadcast], except: [:get_tx], filter: ->(_cmd) { true }) }
        .to raise_error(ArgumentError, /at most one/)
    end
  end

  describe '#allows?' do
    context 'with no options (default)' do
      subject(:specifier) { described_class.new }

      it 'allows any command' do
        expect(specifier.allows?(:broadcast)).to be true
        expect(specifier.allows?(:get_tx)).to be true
        expect(specifier.allows?(:anything)).to be true
      end
    end

    context 'with only:' do
      subject(:specifier) { described_class.new(only: [:broadcast]) }

      it 'allows listed commands' do
        expect(specifier.allows?(:broadcast)).to be true
      end

      it 'rejects unlisted commands' do
        expect(specifier.allows?(:get_tx)).to be false
      end
    end

    context 'with only: []' do
      subject(:specifier) { described_class.new(only: []) }

      it 'allows nothing' do
        expect(specifier.allows?(:broadcast)).to be false
        expect(specifier.allows?(:get_tx)).to be false
      end
    end

    context 'with except:' do
      subject(:specifier) { described_class.new(except: [:broadcast]) }

      it 'rejects listed commands' do
        expect(specifier.allows?(:broadcast)).to be false
      end

      it 'allows unlisted commands' do
        expect(specifier.allows?(:get_tx)).to be true
      end
    end

    context 'with except: []' do
      subject(:specifier) { described_class.new(except: []) }

      it 'allows everything' do
        expect(specifier.allows?(:broadcast)).to be true
        expect(specifier.allows?(:get_tx)).to be true
      end
    end

    context 'with filter:' do
      subject(:specifier) { described_class.new(filter: ->(cmd) { cmd.to_s.start_with?('get_') }) }

      it 'allows commands where the predicate returns truthy' do
        expect(specifier.allows?(:get_tx)).to be true
      end

      it 'rejects commands where the predicate returns falsy' do
        expect(specifier.allows?(:broadcast)).to be false
      end
    end

    context 'with String values in only:' do
      subject(:specifier) { described_class.new(only: %w[broadcast get_tx]) }

      it 'coerces strings to symbols and allows them' do
        expect(specifier.allows?(:broadcast)).to be true
        expect(specifier.allows?(:get_tx)).to be true
      end

      it 'rejects unlisted commands' do
        expect(specifier.allows?(:other)).to be false
      end
    end

    context 'with String values in except:' do
      subject(:specifier) { described_class.new(except: %w[broadcast]) }

      it 'coerces strings to symbols and rejects them' do
        expect(specifier.allows?(:broadcast)).to be false
      end

      it 'allows commands not in the list' do
        expect(specifier.allows?(:get_tx)).to be true
      end
    end

    context 'with filter: that raises' do
      subject(:specifier) { described_class.new(filter: ->(_cmd) { raise 'filter error' }) }

      it 'propagates the exception' do
        expect { specifier.allows?(:broadcast) }.to raise_error(RuntimeError, 'filter error')
      end
    end
  end
end
