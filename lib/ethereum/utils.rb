require 'digest/sha3'

module Ethereum
  module Utils

    extend self

    ZERO_BYTE = "\x00".b.freeze

    INT_MAX = 2**256 - 1
    INT_MIN = -2**255 + 1

    def keccak_256(x)
      Digest::SHA3.new(256).digest(x)
    end

    def keccak_rlp(x)
      keccak_256 RLP.encode(x)
    end

    def ceil32(x)
      x % 32 == 0 ? x : (x + 32 - x%32)
    end

    def big_endian_to_int(s)
      RLP::Sedes.big_endian_int.deserialize s.sub(/^(\x00)+/, '')
    end

    def int_to_big_endian(n)
      RLP::Sedes.big_endian_int.serialize n
    end

    def zpad(x, l)
      (ZERO_BYTE * [0, l - x.size].max + x).b
    end

    def zpad_int(n, l=32)
      zpad encode_int(n), l
    end

    def encode_int(n)
      raise ArgumentError, "Integer invalid or out of range: #{n}" unless n.is_a?(Integer) && n >= 0 && n <= INT_MAX
      int_to_big_endian n
    end

  end
end
