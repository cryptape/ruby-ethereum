# -*- encoding : ascii-8bit -*-

module Ethereum
  module BaseConvert

    BaseSymbols = {
      2   => '01'.freeze,
      10  => '0123456789'.freeze,
      16  => '0123456789abcdef'.freeze,
      32  => 'abcdefghijklmnopqrstuvwxyz234567'.freeze,
      58  => '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'.freeze,
      256 => 256.times.map {|i| i.chr }.join.freeze
    }.freeze

    extend self

    def symbols(base)
      BaseSymbols[base] or raise ArgumentError, "invalid base!"
    end

    def convert(s, from, to, minlen=0)
      return Utils.lpad(s, symbols(from)[0], minlen) if from == to
      encode decode(s, from), to, minlen
    end

    def encode(v, base, minlen)
      syms = symbols(base)

      result = ''
      while v > 0
        result = syms[v % base] + result
        v /= base
      end

      Utils.lpad result, syms[0], minlen
    end

    def decode(s, base)
      syms = symbols(base)
      s = s.downcase if base == 16

      result = 0
      while s.size > 0
        result *= base
        result += syms.index(s[0])
        s = s[1..-1]
      end

      result
    end

  end
end
