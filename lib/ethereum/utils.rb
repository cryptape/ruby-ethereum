# -*- encoding : ascii-8bit -*-

require 'digest'
require 'digest/sha3'

module Ethereum
  module Utils

    extend self

    include Constant

    ##
    # Not the keccak in sha3, although it's underlying lib named SHA3
    #
    def keccak256(x)
      Digest::SHA3.new(256).digest(x)
    end

    def keccak256_rlp(x)
      keccak256 RLP.encode(x)
    end

    def sha256(x)
      Digest::SHA256.digest x
    end

    def double_sha256(x)
      sha256 sha256(x)
    end

    def ceil32(x)
      x % 32 == 0 ? x : (x + 32 - x%32)
    end

    def encode_hex(b)
      RLP::Utils.encode_hex b
    end

    def decode_hex(s)
      RLP::Utils.decode_hex s
    end

    def big_endian_to_int(s)
      RLP::Sedes.big_endian_int.deserialize s.sub(/^(\x00)+/, '')
    end

    def int_to_big_endian(n)
      RLP::Sedes.big_endian_int.serialize n
    end

    def lpad(x, symbol, l)
      return x if x.size >= l
      symbol * (l - x.size) + x
    end

    def zpad(x, l)
      lpad x, BYTE_ZERO, l
    end

    def zpad_int(n, l=32)
      zpad encode_int(n), l
    end

    def zpad_hex(s, l=32)
      zpad decode_hex(s), l
    end

    def encode_int(n)
      raise ArgumentError, "Integer invalid or out of range: #{n}" unless n.is_a?(Integer) && n >= 0 && n <= UINT_MAX
      int_to_big_endian n
    end

    def decode_int(v)
      raise ArgumentError, "No leading zero bytes allowed for integers" if v.size > 0 && (v[0] == Constant::BYTE_ZERO || v[0] == 0)
      big_endian_to_int v
    end

  end
end
