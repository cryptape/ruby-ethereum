require 'ethereum/abi/type'

module Ethereum

  ##
  # Contract ABI encoding and decoding.
  #
  # @see https://github.com/ethereum/wiki/wiki/Ethereum-Contract-ABI
  #
  module ABI


    extend self

    ##
    # Encodes multiple arguments using the head/tail mechanism.
    #
    def encode(types, args)
      head_size = 0
      #parsed_types = types.map {|t| parse_type(t) }
      #sizes = parsed_types.map {|t| }

    end

    def decode

    end

  end

end
