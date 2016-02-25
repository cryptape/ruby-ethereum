# -*- encoding : ascii-8bit -*-

module Ethereum
  class Address

    BLANK = ''.freeze
    ZERO = ("\x00"*20).freeze

    CREATE_CONTRACT = BLANK

    def initialize(s)
      @bytes = parse s
    end

    def to_bytes(extended=false)
      extended ? "#{@bytes}#{checksum}" : @bytes
    end

    def to_hex(extended=false)
      Utils.encode_hex to_bytes(extended)
    end

    def checksum(bytes=nil)
      Utils.keccak256(bytes||@bytes)[0,4]
    end

    def blank?
      @bytes == BLANK
    end

    private

    def parse(s)
      case s.size
      when 0
        s
      when 40
        Utils.decode_hex s
      when 42
        raise FormatError, "Invalid address format!" unless s[0,2] == '0x'
        parse s[2..-1]
      when 48
        bytes = Utils.decode_hex s
        parse bytes
      when 50
        raise FormatError, "Invalid address format!" unless s[0,2] == '0x'
        parse s[2..-1]
      when 20
        s
      when 24
        bytes = s[0...-4]
        raise ChecksumError, "Invalid address checksum!" unless s[-4..-1] == checksum(bytes)
        bytes
      else
        raise FormatError, "Invalid address format!"
      end
    end

  end
end
