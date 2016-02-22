# -*- encoding : ascii-8bit -*-

module Ethereum
  module Address

    extend self

    def base58_check_to_bytes(s)
      leadingzbytes = s.match(/^1*/)[0]
      data = Constant::BYTE_ZERO * leadingzbytes.size + BaseConvert.convert(s, 58, 256)

      raise ChecksumError, "double sha256 checksum doesn't match" unless Utils.double_sha256(data[0...-4])[0,4] == data[-4..-1]
      data[1...-4]
    end

    def bytes_to_base58_check(bytes, magicbyte=0)
      bs = "#{magicbyte.chr}#{bytes}"
      leadingzbytes = bs.match(/^#{Constant::BYTE_ZERO}*/)[0]
      checksum = Utils.double_sha256(bs)[0,4]
      '1'*leadingzbytes.size + BaseConvert.convert("#{bs}#{checksum}", 256, 58)
    end

  end
end
