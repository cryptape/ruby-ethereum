module Ethereum

  ##
  # Contract ABI encoding and decoding.
  #
  # @see https://github.com/ethereum/wiki/wiki/Ethereum-Contract-ABI
  #
  module ABI

    class TypeParseError < StandardError; end

    extend self

    ##
    # Encodes multiple arguments using the head/tail mechanism.
    #
    def encode(types, args)
      head_size = 0

    end

    def decode

    end


    ##
    # Crazy regexp to seperate out base type component (eg. uint), size (eg.
    # 256, 128x128, nil), array component (eg. [], [45], nil)
    #
    def parse_type(type)
      _, base, sub, arr = /([a-z]*)([0-9]*x?[0-9]*)((\[[0-9]*\])*)/.match(type).to_a

      arrlist = arr.scan(/\[[0-9]*\]/)
      raise TypeParseError, "Unknown characters found in array declaration" if arrlist.join != arr

      case base
      when 'string'
        raise TypeParseError, "String type must have no suffix or numerical suffix" unless sub.empty?
      when 'bytes'
        raise TypeParseError, "Maximum 32 bytes for fixed-length string or bytes" unless sub.empty? || sub.to_i <= 32
      when 'uint', 'int'
        raise TypeParseError, "Integer type must have numerical suffix" unless sub =~ /^[0-9]+$/

        size = sub.to_i
        raise TypeParseError, "Integer size out of bounds" unless size >= 8 && size <= 256
        raise TypeParseError, "Integer size must be multiple of 8" unless size % 8 == 0
      when 'ureal', 'real', 'fixed', 'ufixed'
        raise TypeParseError, "Real type must have suffix of form <high>x<low>, e.g. 128x128" unless sub =~ /^[0-9]+x[0-9]+$/

        high, low = sub.split('x').map(&:to_i)
        total = high + low

        raise TypeParseError, "Real size out of bounds (max 32 bytes)" unless total >= 8 && total <= 256
        raise TypeParseError, "Real high/low sizes must be multiples of 8" unless high % 8 == 0 && low % 8 == 0
      when 'hash'
        raise TypeParseError, "Hash type must have numerical suffix" unless sub =~ /^[0-9]+$/
      when 'address'
        raise TypeParseError, "Address cannot have suffix" unless sub.empty?
      when 'bool'
        raise TypeParseError, "Bool cannot have suffix" unless sub.empty?
      else
        raise TypeParseError, "Unrecognized type base: #{base}"
      end

      [base, sub, arrlist.map {|x| x[1...-1].to_i }]
    end

  end

end
