# -*- encoding : ascii-8bit -*-

module Ethereum
  class Jacobian

    P = Secp256k1::P
    A = Secp256k1::A

    attr :x, :y, :z

    class <<self
      def fast_mul(a, n)
        new(a).mul(n).to_a
      end

      def fast_add(a, b)
        (new(a) + new(b)).to_a
      end
    end

    def initialize(*args)
      xyz = args[0].instance_of?(Array) ? args[0] : args
      @x = xyz[0]
      @y = xyz[1]
      @z = xyz[2] || 1
    end

    def add(q)
      raise ArgumentError, "can only apply to Jacobian" unless another.is_a?(Jacobian)

      p = self
      return q if p.y == 0
      return p if q.y == 0

      u1 = (p.x * q.z**2) % P
      u2 = (q.x * p.z**2) % P
      s1 = (p.y * q.z**3) % P
      s2 = (q.y * p.z**3) % P

      if u1 == u2
        return s1 != s2 ? Jacobian.new(0, 0, 1) : p.double
      end

      h = u2 - u1
      r = s2 - s1
      h2 = (h * h) % P
      h3 = (h * h2) % P
      u1h2 = (u1 * h2) % P

      nx = (r**2 - h3 - 2*u1h2) % P
      ny = (r*(u1h2 - nx) - s1*h3) % P
      nz = (h * p.z * q.z) % P

      Jacobian.new(nx, ny, nz)
    end
    alias :+ :add

    def mul(n)
      return Jacobian.new(0, 0, 1) if y == 0 || n == 0
      return self if n == 1
      return mul(n % N) if n < 0 || n >= N

      if n % 2 == 0
        mul(n/2).double
      else
        mul(n/2).double.add(self)
      end
    end
    alias :* :mul

    def double
      return Jacobian.new(0, 0, 0) if y == 0

      ysq = (y ** 2) % P
      s = (4 * x * ysq) % P
      m = (3 * x**2 + A * z**4) % P

      nx = (m**2 - 2*s) % P
      ny = (m * (s - nx) - 8 * ysq**2) % P
      nz = (2 * y * z) % P

      Jacobian.new(nx, ny, nz)
    end

    def to_a
      nz = inv z, P
      [(x * nz**2) % P, (y * nz**3) % P]
    end

    private

    def inv(a, n)
      return 0 if a == 0

      lm, hm = 1, 0
      low, high = a % n, n
      while low > 1
        r = high / low
        nm, nn = hm - lm*r, high - low*r
        lm, low, hm, high = nm, nn, lm, low
      end

      lm % n
    end

  end
end
