# frozen_string_literal: true

require 'mkmf'

# Check for __uint128_t support — required for efficient 256-bit arithmetic.
# If unavailable (e.g. MSVC), create a dummy Makefile that builds nothing so
# the gem still installs cleanly and falls back to pure-Ruby arithmetic.
unless have_type('__uint128_t')
  File.write('Makefile', <<~MAKEFILE)
    all:
    \t@echo "Skipping native extension: __uint128_t not available"
    install:
    clean:
  MAKEFILE
  return
end

$CFLAGS += ' -O2 -Wall -std=c99'

# Auto-detect all .c files in this directory so additional source files
# (field.c, scalar.c, jacobian.c) are compiled automatically in later tasks.
$srcs = Dir.glob("#{$srcdir}/*.c").map { |f| File.basename(f) }

create_makefile('bsv/secp256k1_native')
