# -*- encoding : ascii-8bit -*-

require 'digest'
require 'digest/sha3'
require 'openssl'

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

    def keccak512(x)
      Digest::SHA3.new(512).digest(x)
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

    def ripemd160(x)
      Digest::RMD160.digest x
    end

    def hash160(x)
      ripemd160 sha256(x)
    end

    def hash160_hex(x)
      encode_hex hash160(x)
    end

    def mod_exp(x, y, n)
      x.to_bn.mod_exp(y, n).to_i
    end

    def to_signed(i)
      i > Constant::INT_MAX ? (i-Constant::TT256) : i
    end

    def base58_check_to_bytes(s)
      leadingzbytes = s.match(/^1*/)[0]
      data = Constant::BYTE_ZERO * leadingzbytes.size + BaseConvert.convert(s, 58, 256)

      raise ChecksumError, "double sha256 checksum doesn't match" unless double_sha256(data[0...-4])[0,4] == data[-4..-1]
      data[1...-4]
    end

    def bytes_to_base58_check(bytes, magicbyte=0)
      bs = "#{magicbyte.chr}#{bytes}"
      leadingzbytes = bs.match(/^#{Constant::BYTE_ZERO}*/)[0]
      checksum = double_sha256(bs)[0,4]
      '1'*leadingzbytes.size + BaseConvert.convert("#{bs}#{checksum}", 256, 58)
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

    def zunpad(x)
      x.sub /^\x00+/, ''
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

    def bytearray_to_int(arr)
      o = 0
      arr.each {|x| o = (o << 8) + x }
      o
    end

    def int_array_to_bytes(arr)
      arr.pack('C*')
    end

    def bytes_to_int_array(bytes)
      bytes.unpack('C*')
    end

    def coerce_to_int(x)
      if x.is_a?(Numeric)
        x
      elsif x.size == 40
        big_endian_to_int decode_hex(x)
      else
        big_endian_to_int x
      end
    end

    def coerce_to_bytes(x)
      if x.is_a?(Numeric)
        int_to_big_endian x
      elsif x.size == 40
        decode_hex(x)
      else
        x
      end
    end

    def coerce_addr_to_hex(x)
      if x.is_a?(Numeric)
        encode_hex zpad(int_to_big_endian(x), 20)
      elsif x.size == 40 || x.size == 0
        x
      else
        encode_hex zpad(x, 20)[-20..-1]
      end
    end

    def normalize_address(x, allow_blank: false)
      address = Address.new(x)
      raise ValueError, "address is blank" if !allow_blank && address.blank?
      address.to_bytes
    end

  end
end
