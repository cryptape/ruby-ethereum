require 'digest/sha3'

module Ethereum
  module Utils

    extend self

    HEX_VALUES = (0..15).inject({}) {|h, i| h[i.to_s(16).b] = i; h}.freeze

    def keccak_256(x)
      Digest::SHA3.new(256).digest(x)
    end

    def keccak_rlp(x)
      keccak_256 RLP.encode(x)
    end

    ##
    # convert string s to nibbles (half-bytes)
    #
    # @example
    #   str_to_nibbles('') # => []
    #   str_to_nibbles('h') # => [6, 8]
    #   str_to_nibbles('he') # => [6, 8, 6, 5]
    #   str_to_nibbles('hello') # => [6, 8, 6, 5, 6, 12, 6, 12, 6, 15]
    #
    # @param s [String] any string
    #
    # @return [Array[Integer]] array of nibbles presented as integer smaller
    #   than 16
    #
    def str_to_nibbles(s)
      RLP::Utils.encode_hex(s).each_char.map {|nibble| HEX_VALUES[nibble] }
    end
  end
end
