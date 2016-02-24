require 'openssl'

module Ethereum
  class PublicKey

    attr :raw

    def initialize(raw)
      @raw = raw
    end

    def encode(fmt)
      case fmt
      when :decimal
        value
      when :bin
        "\x04#{BaseConvert.encode(value[0], 256, 32)}#{BaseConvert.encode(value[1], 256, 32)}"
      when :bin_compressed
        "#{(2+(value[1]%2)).chr}#{BaseConvert.encode(value[0], 256, 32)}"
      when :hex
        "04#{BaseConvert.encode(value[0], 16, 64)}#{BaseConvert.encode(value[1], 16, 64)}"
      when :hex_compressed
        "0#{2+(value[1]%2)}#{BaseConvert.encode(value[0], 16, 64)}"
      when :bin_electrum
        "#{BaseConvert.encode(value[0], 256, 32)}#{BaseConvert.encode(value[1], 256, 32)}"
      when :hex_electrum
        "#{BaseConvert.encode(value[0], 16, 64)}#{BaseConvert.encode(value[1], 16, 64)}"
      else
        raise FormatError, "Invalid format!"
      end
    end

    def decode(fmt=nil)
      fmt ||= format

      case fmt
      when :decimal
        raw
      when :bin
        [BaseConvert.decode(raw[1,32], 256), BaseConvert.decode(raw[33,32], 256)]
      when :bin_compressed
        x = BaseConvert.decode raw[1,32], 256
        m = x*x*x + Secp256k1::A*x + Secp256k1::B
        n = m.to_bn.mod_exp((Secp256k1::P+1)/4, Secp256k1::P).to_i
        q = (n + raw[0].ord) % 2
        y = q == 1 ? (Secp256k1::P - n) : n
        [x, y]
      when :hex
        [BaseConvert.decode(raw[2,64], 16), BaseConvert.decode(raw[66,64], 16)]
      when :hex_compressed
        PublicKey.new(Utils.decode_hex(raw)).decode :bin_compressed
      when :bin_electrum
        [BaseConvert.decode(raw[0,32], 256), BaseConvert.decode(raw[32,32], 256)]
      when :hex_electrum
        [BaseConvert.decode(raw[0,64], 16), BaseConvert.decode(raw[64,128], 16)]
      else
        raise FormatError, "Invalid format!"
      end
    end

    def value
      @value ||= decode
    end

    def format
      return :decimal if raw.is_a?(Array)
      return :bin if raw.size == 65 && raw[0] == "\x04"
      return :hex if raw.size == 130 && raw[0, 2] == '04'
      return :bin_compressed if raw.size == 33 && "\x02\x03".include?(raw[0])
      return :hex_compressed if raw.size == 66 && %w(02 03).include?(raw[0,2])
      return :bin_electrum if raw.size == 64
      return :hex_electrum if raw.size == 128

      raise FormatError, "Pubkey is not in recognized format"
    end

    def to_bitcoin_address(magicbyte=0)
      bytes = encode(:bin)
      Utils.bytes_to_base58_check Utils.hash160(bytes), magicbyte
    end

    def to_address(extended=false)
      bytes = Utils.keccak256(encode(:bin)[1..-1])[-20..-1]
      Address.new(bytes).to_bytes(extended)
    end

  end
end
