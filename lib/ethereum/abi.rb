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
      parsed_types = types.map {|t| Type.parse(t) }

      sizes = parsed_types.map(&:size)
      head_size = (0...args.size).map {|i| sizes[i] || 32 }.reduce(0, &:+)

      head, tail = '', ''
      args.each_with_index do |arg, i|
        if sizes[i]
          head += encode_type(parsed_types[i], arg)
        else
          head += encode_type(Type.size_type, head_size + tail.size)
          tail += encode_type(parsed_types[i], arg)
        end
      end

      "#{head}#{tail}"
    end

    def decode

    end

    ##
    # Encodes a single value (static or dynamic).
    #
    def encode_type(type, arg)

    end
  end

end
