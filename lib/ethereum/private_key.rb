# -*- encoding : ascii-8bit -*-

module Ethereum
  class PrivateKey

    attr :raw

    def initialize(raw)
      @raw = raw
    end

    def encode(fmt, vbyte=0)
      return self.class.new(decode).encode(fmt, vbyte) unless raw.is_a?(Numeric)

      case fmt
      when :decimal
        raw
      when :bin
        BaseConvert.encode(raw, 256, 32)
      when :bin_compressed
        "#{BaseConvert.encode(raw, 256, 32)}\x01"
      when :hex
        BaseConvert.encode(raw, 16, 64)
      when :hex_compressed
        "#{BaseConvert.encode(raw, 16, 64)}01"
      when :wif
        Address.bytes_to_base58_check(encode(:bin), 128+vbyte)
      when :wif_compressed
        Address.bytes_to_base58_check(encode(:bin_compressed), 128+vbyte)
      else
        raise ArgumentError, "invalid format: #{fmt}"
      end
    end

    def decode(fmt=nil)
      fmt ||= format

      case fmt
      when :decimal
        raw
      when :bin
        BaseConvert.decode(raw, 256)
      when :bin_compressed
        BaseConvert.decode(raw[0,32], 256)
      when :hex
        BaseConvert.decode(raw, 16)
      when :hex_compressed
        BaseConvert.decode(raw[0,64], 16)
      when :wif
        BaseConvert.decode Address.base58_check_to_bytes(raw), 256
      when :wif_compressed
        BaseConvert.decode Address.base58_check_to_bytes(raw)[0,32], 256
      else
        raise ArgumentError, "WIF does not represent privkey"
      end
    end

    def format
      return :decimal if raw.is_a?(Numeric)
      return :bin if raw.size == 32
      return :bin_compressed if raw.size == 33
      return :hex if raw.size == 64
      return :hex_compressed if raw.size == 66

      bytes = Address.base58_check_to_bytes raw
      return :wif if bytes.size == 32
      return :wif_compressed if bytes.size == 33

      raise FormatError, "WIF does not represent privkey"
    end

  end
end
