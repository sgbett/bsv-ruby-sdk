# frozen_string_literal: true

# Single-letter parameter names (k, p, q, x, y, z, etc.) match standard
# elliptic-curve mathematical notation and the BSV TypeScript reference SDK
# this module is ported from. The whole-module length cop is disabled because
# the curve implementation (field arithmetic + Jacobian point ops + wNAF
# scalar multiplication + Point class) intentionally lives in one module to
# keep the secp256k1 surface coherent.
# rubocop:disable Naming/MethodParameterName, Metrics/ModuleLength

module BSV
  module Primitives
    # Pure Ruby secp256k1 elliptic curve implementation.
    #
    # Provides field arithmetic, point operations with Jacobian coordinates,
    # and windowed-NAF scalar multiplication. Ported from the BSV TypeScript
    # SDK reference implementation.
    #
    # All field operations work on plain Ruby +Integer+ values (arbitrary
    # precision, C-backed in MRI). No external gems required.
    module Secp256k1
      # The secp256k1 field prime: p = 2^256 - 2^32 - 977
      P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F

      # The curve order (number of points on the curve).
      N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

      # Half the curve order, used for low-S normalisation (BIP-62).
      HALF_N = N >> 1

      # Generator point x-coordinate.
      GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798

      # Generator point y-coordinate.
      GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8

      # (P + 1) / 4 — used for modular square root since P ≡ 3 (mod 4).
      P_PLUS1_DIV4 = (P + 1) >> 2

      # 256-bit mask for fast reduction.
      MASK_256 = (1 << 256) - 1

      module_function

      # -------------------------------------------------------------------
      # Byte conversion helpers
      # -------------------------------------------------------------------

      # Convert a big-endian binary string to an Integer.
      #
      # @param bytes [String] binary string (ASCII-8BIT)
      # @return [Integer]
      def bytes_to_int(bytes)
        # C-backed hex route is the fastest pure-Ruby byte→integer path (10x faster than inject).
        bytes.unpack1('H*').to_i(16)
      end

      # Convert an Integer to a fixed-length big-endian binary string.
      #
      # @param n [Integer] the integer to convert
      # @param length [Integer] desired byte length (default 32)
      # @return [String] binary string (ASCII-8BIT)
      def int_to_bytes(n, length = 32)
        raise ArgumentError, 'negative integer' if n.negative?

        # C-backed hex route is the fastest pure-Ruby integer→byte path. Module deliberately avoids OpenSSL.
        hex = n.to_s(16)
        hex = "0#{hex}" if hex.length.odd?
        raise ArgumentError, "integer too large for #{length} bytes" if hex.length > length * 2

        hex = hex.rjust(length * 2, '0')
        [hex].pack('H*')
      end

      # -------------------------------------------------------------------
      # Field arithmetic (mod P)
      # -------------------------------------------------------------------

      # Fast reduction modulo the secp256k1 prime.
      #
      # Exploits the structure P = 2^256 - 2^32 - 977 to avoid generic
      # modular division. Two folding passes plus a conditional subtraction.
      #
      # @param x [Integer] non-negative integer
      # @return [Integer] x mod P, in range [0, P)
      def fred(x)
        # First fold
        hi = x >> 256
        x = (x & MASK_256) + (hi << 32) + (hi * 977)

        # Second fold (hi <= 2^32 + 977, so one more pass suffices)
        hi = x >> 256
        x = (x & MASK_256) + (hi << 32) + (hi * 977)

        # Final conditional subtraction
        x >= P ? x - P : x
      end

      # Modular multiplication in the field.
      def fmul(a, b)
        fred(a * b)
      end

      # Modular squaring in the field.
      def fsqr(a)
        fred(a * a)
      end

      # Modular addition in the field.
      def fadd(a, b)
        fred(a + b)
      end

      # Modular subtraction in the field.
      def fsub(a, b)
        a >= b ? a - b : P - (b - a)
      end

      # Modular negation in the field.
      def fneg(a)
        a.zero? ? 0 : P - a
      end

      # Modular multiplicative inverse in the field (Fermat's little theorem).
      #
      # @param a [Integer] value to invert (must be non-zero mod P)
      # @return [Integer] a^(P-2) mod P
      # @raise [ArgumentError] if a is zero mod P
      def finv(a)
        raise ArgumentError, 'field inverse is undefined for zero' if (a % P).zero?

        a.pow(P - 2, P)
      end

      # Modular square root in the field.
      #
      # Uses the identity sqrt(a) = a^((P+1)/4) mod P, valid because
      # P ≡ 3 (mod 4). Returns +nil+ if +a+ is not a quadratic residue.
      #
      # @param a [Integer]
      # @return [Integer, nil] the square root, or nil if none exists
      def fsqrt(a)
        r = a.pow(P_PLUS1_DIV4, P)
        fsqr(r) == (a % P) ? r : nil
      end

      # -------------------------------------------------------------------
      # Scalar arithmetic (mod N)
      # -------------------------------------------------------------------

      # Reduce modulo the curve order.
      def scalar_mod(a)
        r = a % N
        r += N if r.negative?
        r
      end

      # Scalar multiplicative inverse (Fermat).
      #
      # @raise [ArgumentError] if a is zero mod N
      def scalar_inv(a)
        raise ArgumentError, 'scalar inverse is undefined for zero' if (a % N).zero?

        a.pow(N - 2, N)
      end

      # Scalar multiplication mod N.
      def scalar_mul(a, b)
        (a * b) % N
      end

      # Scalar addition mod N.
      def scalar_add(a, b)
        (a + b) % N
      end

      # -------------------------------------------------------------------
      # Jacobian point operations (internal)
      #
      # Points are represented as [X, Y, Z] arrays of Integers.
      # The point at infinity is [0, 1, 0].
      # -------------------------------------------------------------------

      # @!visibility private
      JP_INFINITY = [0, 1, 0].freeze

      # Double a Jacobian point.
      #
      # Formula from hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html
      # (a=0 for secp256k1).
      #
      # @param p [Array(Integer, Integer, Integer)] Jacobian point [X, Y, Z]
      # @return [Array(Integer, Integer, Integer)]
      def jp_double(p)
        x1, y1, z1 = p
        return JP_INFINITY if y1.zero?

        y1sq = fsqr(y1)
        s = fmul(4, fmul(x1, y1sq))
        m = fmul(3, fsqr(x1)) # a=0 for secp256k1
        x3 = fsub(fsqr(m), fmul(2, s))
        y3 = fsub(fmul(m, fsub(s, x3)), fmul(8, fsqr(y1sq)))
        z3 = fmul(2, fmul(y1, z1))
        [x3, y3, z3]
      end

      # Add two Jacobian points.
      #
      # @param p [Array] first Jacobian point
      # @param q [Array] second Jacobian point
      # @return [Array] resulting Jacobian point
      def jp_add(p, q)
        _px, _py, pz = p
        _qx, _qy, qz = q
        return q if pz.zero?
        return p if qz.zero?

        z1z1 = fsqr(pz)
        z2z2 = fsqr(qz)
        u1 = fmul(p[0], z2z2)
        u2 = fmul(q[0], z1z1)
        s1 = fmul(p[1], fmul(z2z2, qz))
        s2 = fmul(q[1], fmul(z1z1, pz))

        h = fsub(u2, u1)
        r = fsub(s2, s1)

        if h.zero?
          return r.zero? ? jp_double(p) : JP_INFINITY
        end

        hh = fsqr(h)
        hhh = fmul(h, hh)
        v = fmul(u1, hh)

        x3 = fsub(fsub(fsqr(r), hhh), fmul(2, v))
        y3 = fsub(fmul(r, fsub(v, x3)), fmul(s1, hhh))
        z3 = fmul(h, fmul(pz, qz))
        [x3, y3, z3]
      end

      # Convert a Jacobian point to affine coordinates.
      #
      # @param jp [Array(Integer, Integer, Integer)]
      # @return [Array(Integer, Integer)] affine [x, y], or nil for infinity
      def jp_to_affine(jp)
        _x, _y, z = jp
        return nil if z.zero?

        zinv = finv(z)
        zinv2 = fsqr(zinv)
        x = fmul(jp[0], zinv2)
        y = fmul(jp[1], fmul(zinv2, zinv))
        [x, y]
      end

      # -------------------------------------------------------------------
      # Windowed-NAF scalar multiplication (variable-time, public scalars)
      # -------------------------------------------------------------------

      # @!visibility private
      # Maximum number of entries kept in the wNAF precomputation cache.
      # Bounds memory usage for long-running processes (e.g. servers).
      WNAF_CACHE_MAX = 512

      # @!visibility private
      # Cache for precomputed wNAF tables, keyed by "window:x:y".
      # Evicts oldest entry when the LRU limit is reached.
      WNAF_TABLE_CACHE = {} # rubocop:disable Style/MutableConstant

      # @!visibility private
      # Multiply a point by a scalar using windowed-NAF.
      #
      # Variable-time algorithm — suitable only for public scalars (e.g.
      # signature verification). Secret-scalar paths MUST use
      # {scalar_multiply_ct} instead.
      #
      # Internal method — use {Point#mul} or {Point#mul_ct} instead.
      # Exposed as a module function only so the nested Point class can
      # call it; not part of the public API.
      #
      # @param k [Integer] the scalar (must be in [1, N))
      # @param px [Integer] affine x-coordinate of the base point
      # @param py [Integer] affine y-coordinate of the base point
      # @param window [Integer] wNAF window size (default 5)
      # @return [Array(Integer, Integer, Integer)] result as Jacobian point
      def scalar_multiply_wnaf(k, px, py, window = 5)
        return JP_INFINITY if k.zero?

        cache_key = "#{window}:#{px.to_s(16)}:#{py.to_s(16)}"
        tbl = WNAF_TABLE_CACHE[cache_key]

        if tbl.nil?
          # Evict the oldest entry when the cache is full (simple LRU).
          WNAF_TABLE_CACHE.delete(WNAF_TABLE_CACHE.keys.first) if WNAF_TABLE_CACHE.size >= WNAF_CACHE_MAX

          tbl_size = 1 << (window - 1) # e.g. w=5 -> 16 entries
          tbl = Array.new(tbl_size)
          tbl[0] = [px, py, 1]
          two_p = jp_double(tbl[0])
          1.upto(tbl_size - 1) do |i|
            tbl[i] = jp_add(tbl[i - 1], two_p)
          end
          WNAF_TABLE_CACHE[cache_key] = tbl
        end

        # Build wNAF representation
        w_big = 1 << window
        w_half = w_big >> 1
        wnaf = []
        k_tmp = k
        while k_tmp.positive?
          if k_tmp.odd?
            z = k_tmp & (w_big - 1)
            z -= w_big if z > w_half
            wnaf << z
            k_tmp -= z
          else
            wnaf << 0
          end
          k_tmp >>= 1
        end

        # Accumulate from MSB to LSB
        q = JP_INFINITY
        (wnaf.length - 1).downto(0) do |i|
          q = jp_double(q)
          di = wnaf[i]
          next if di.zero?

          idx = di.abs >> 1
          addend = di.positive? ? tbl[idx] : jp_neg(tbl[idx])
          q = jp_add(q, addend)
        end
        q
      end

      # -------------------------------------------------------------------
      # Montgomery ladder scalar multiplication (constant-time, secret scalars)
      # -------------------------------------------------------------------

      # @!visibility private
      # Multiply a point by a scalar using the Montgomery ladder.
      #
      # Executes a fixed number of iterations (256) with one +jp_double+
      # and one +jp_add+ per iteration regardless of the scalar value.
      # Use this for ALL secret-scalar paths (key generation, signing,
      # ECDH, BIP-32 derivation).
      #
      # *Best-effort constant-time in interpreted Ruby.* The branch on
      # +bit+ selects which register receives each operation, and both
      # operations always execute. However, Ruby's interpreter, GC, and
      # the early-return branches in +jp_add+/+jp_double+ (for infinity
      # edge cases) mean true constant-time execution is not achievable
      # without native code. This matches the ts-sdk's TypeScript
      # implementation, which has the same structural properties. For
      # production deployments requiring side-channel resistance beyond
      # what an interpreted language can offer, use a native secp256k1
      # library (e.g. libsecp256k1 via FFI).
      #
      # Internal method — use {Point#mul_ct} instead. Not part of the
      # public API.
      #
      # @param k [Integer] secret scalar (must be in [1, N))
      # @param px [Integer] affine x-coordinate of the base point
      # @param py [Integer] affine y-coordinate of the base point
      # @return [Array(Integer, Integer, Integer)] result as Jacobian point
      def scalar_multiply_ct(k, px, py)
        return JP_INFINITY if k.zero?

        # r0 accumulates the result; r1 = r0 + base_point at all times.
        r0 = JP_INFINITY
        r1 = [px, py, 1]

        256.times do |i|
          bit = (k >> (255 - i)) & 1
          if bit.zero?
            r1 = jp_add(r0, r1)
            r0 = jp_double(r0)
          else
            r0 = jp_add(r0, r1)
            r1 = jp_double(r1)
          end
        end

        r0
      end

      # Negate a Jacobian point.
      def jp_neg(p)
        return p if p[2].zero?

        [p[0], fneg(p[1]), p[2]]
      end

      # -------------------------------------------------------------------
      # Point class
      # -------------------------------------------------------------------

      # An elliptic curve point on secp256k1.
      #
      # Stores affine coordinates (x, y) or represents the point at infinity.
      # Scalar multiplication uses Jacobian coordinates internally with
      # windowed-NAF for performance.
      class Point
        # @return [Integer, nil] x-coordinate (nil for infinity)
        attr_reader :x

        # @return [Integer, nil] y-coordinate (nil for infinity)
        attr_reader :y

        # @param x [Integer, nil] x-coordinate (nil for infinity)
        # @param y [Integer, nil] y-coordinate (nil for infinity)
        def initialize(x, y)
          @x = x
          @y = y
        end

        # The point at infinity (additive identity).
        #
        # @return [Point]
        def self.infinity
          new(nil, nil)
        end

        # The generator point G.
        #
        # @return [Point]
        def self.generator
          @generator ||= new(GX, GY)
        end

        # Deserialise a point from compressed (33 bytes) or uncompressed
        # (65 bytes) SEC1 encoding.
        #
        # @param bytes [String] binary string
        # @return [Point]
        # @raise [ArgumentError] if the encoding is invalid or the point
        #   is not on the curve
        def self.from_bytes(bytes)
          bytes = bytes.b if bytes.encoding != Encoding::BINARY
          prefix = bytes.getbyte(0)

          case prefix
          when 0x04 # Uncompressed
            raise ArgumentError, 'invalid uncompressed point length' unless bytes.length == 65

            x = Secp256k1.bytes_to_int(bytes[1, 32])
            y = Secp256k1.bytes_to_int(bytes[33, 32])
            raise ArgumentError, 'x coordinate out of field range' if x >= P
            raise ArgumentError, 'y coordinate out of field range' if y >= P

            pt = new(x, y)
            raise ArgumentError, 'point is not on the curve' unless pt.on_curve?

            pt
          when 0x02, 0x03 # Compressed
            raise ArgumentError, 'invalid compressed point length' unless bytes.length == 33

            x = Secp256k1.bytes_to_int(bytes[1, 32])
            raise ArgumentError, 'x coordinate out of field range' if x >= P

            y_squared = Secp256k1.fadd(Secp256k1.fmul(Secp256k1.fsqr(x), x), 7)
            y = Secp256k1.fsqrt(y_squared)
            raise ArgumentError, 'invalid point: x not on curve' if y.nil?

            # Ensure y-parity matches prefix
            y = Secp256k1.fneg(y) if (y.odd? ? 0x03 : 0x02) != prefix

            new(x, y)
          else
            raise ArgumentError, "unknown point prefix: 0x#{prefix.to_s(16).rjust(2, '0')}"
          end
        end

        # Whether this is the point at infinity.
        #
        # @return [Boolean]
        def infinity?
          @x.nil?
        end

        # Whether this point lies on the secp256k1 curve (y² = x³ + 7).
        #
        # @return [Boolean]
        def on_curve?
          return true if infinity?

          lhs = Secp256k1.fsqr(@y)
          rhs = Secp256k1.fadd(Secp256k1.fmul(Secp256k1.fsqr(@x), @x), 7)
          lhs == rhs
        end

        # Serialise the point in SEC1 format.
        #
        # @param format [:compressed, :uncompressed]
        # @return [String] binary string (33 or 65 bytes)
        # @raise [RuntimeError] if the point is at infinity
        def to_octet_string(format = :compressed)
          raise 'cannot serialise point at infinity' if infinity?

          case format
          when :compressed
            prefix = @y.odd? ? "\x03".b : "\x02".b
            prefix + Secp256k1.int_to_bytes(@x, 32)
          when :uncompressed
            "\x04".b + Secp256k1.int_to_bytes(@x, 32) + Secp256k1.int_to_bytes(@y, 32)
          else
            raise ArgumentError, "unknown format: #{format}"
          end
        end

        # Scalar multiplication: self * scalar (variable-time, wNAF).
        #
        # Suitable for public scalars only (e.g. signature verification).
        # For secret-scalar paths use {#mul_ct}.
        #
        # @param scalar [Integer] the scalar multiplier
        # @return [Point] the resulting point
        def mul(scalar)
          return self.class.infinity if scalar.zero? || infinity?

          scalar %= N
          return self.class.infinity if scalar.zero?

          jp = Secp256k1.scalar_multiply_wnaf(scalar, @x, @y)
          affine = Secp256k1.jp_to_affine(jp)
          return self.class.infinity if affine.nil?

          self.class.new(affine[0], affine[1])
        end

        # Constant-time scalar multiplication: self * scalar (Montgomery ladder).
        #
        # Processes all 256 bits unconditionally so execution time does not
        # depend on the scalar value. Use this for secret-scalar paths:
        # key generation, signing, and ECDH shared-secret derivation.
        #
        # @param scalar [Integer] the secret scalar multiplier
        # @return [Point] the resulting point
        def mul_ct(scalar)
          return self.class.infinity if scalar.zero? || infinity?

          scalar %= N
          return self.class.infinity if scalar.zero?

          jp = Secp256k1.scalar_multiply_ct(scalar, @x, @y)
          affine = Secp256k1.jp_to_affine(jp)
          return self.class.infinity if affine.nil?

          self.class.new(affine[0], affine[1])
        end

        # Point addition: self + other.
        #
        # @param other [Point]
        # @return [Point]
        def add(other)
          return other if infinity?
          return self if other.infinity?

          jp1 = [@x, @y, 1]
          jp2 = [other.x, other.y, 1]
          jp_result = Secp256k1.jp_add(jp1, jp2)
          affine = Secp256k1.jp_to_affine(jp_result)
          return self.class.infinity if affine.nil?

          self.class.new(affine[0], affine[1])
        end

        # Point negation: -self.
        #
        # @return [Point]
        def negate
          return self if infinity?

          self.class.new(@x, Secp256k1.fneg(@y))
        end

        # Equality comparison.
        #
        # @param other [Point]
        # @return [Boolean]
        def ==(other)
          return false unless other.is_a?(Point)

          if infinity? && other.infinity?
            true
          elsif infinity? || other.infinity?
            false
          else
            @x == other.x && @y == other.y
          end
        end
        alias eql? ==

        def hash
          infinity? ? 0 : [@x, @y].hash
        end
      end

      # Load native C acceleration if available.
      # When the extension is compiled, field, scalar, and point operations
      # are replaced with C implementations. The pure-Ruby methods above
      # remain as the readable reference and are used as fallback.
      begin
        require 'bsv/secp256k1_native'

        # Replace field, scalar, and point operations with native C versions.
        #
        # `method(m).to_proc` converts the C singleton method to a Proc,
        # stripping the receiver binding so it can be attached to this module.
        # We define directly on the singleton class (the public module-function
        # surface) only — `module_function` is NOT called again here, because
        # it would re-copy the private Ruby instance method back over our new
        # singleton definition.
        %i[fmul fsqr fadd fsub fneg finv fsqrt fred
           scalar_mod scalar_mul scalar_inv scalar_add
           jp_double jp_add jp_neg].each do |m|
          singleton_class.define_method(m, Secp256k1Native.method(m).to_proc)
        end
      rescue LoadError
        # Extension not compiled — pure-Ruby fallback, no action needed.
      end
    end
  end
end
# rubocop:enable Naming/MethodParameterName, Metrics/ModuleLength
