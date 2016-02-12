require 'ethereum/abi/type'

module Ethereum

  ##
  # Contract ABI encoding and decoding.
  #
  # @see https://github.com/ethereum/wiki/wiki/Ethereum-Contract-ABI
  #
  module ABI

    extend self

    ZERO_BYTE = "\x00".b.freeze

    ##
    # Encodes multiple arguments using the head/tail mechanism.
    #
    def encode(types, args)
      parsed_types = types.map {|t| Type.parse(t) }

      head_size = (0...args.size)
        .map {|i| parsed_types[i].size || 32 }
        .reduce(0, &:+)

      head, tail = '', ''
      args.each_with_index do |arg, i|
        if parsed_types[i].size
          head += encode_type(parsed_types[i], arg)
        else
          head += encode_type(Type.size_type, head_size + tail.size)
          tail += encode_type(parsed_types[i], arg)
        end
      end

      "#{head}#{tail}".b
    end

    def decode

    end

    ##
    # Encodes a single value (static or dynamic).
    #
    # @param type [Ethereum::ABI::Type] value type
    # @param arg [Object] value
    #
    # @return [String] encoded bytes
    #
    def encode_type(type, arg)
      if %w(string bytes).include?(type.base) && type.sub.empty?
        raise ArgumentError, "arg must be a string" unless arg.instance_of?(String)

        size = encode_type Type.size_type, arg.size
        fill = ZERO_BYTE * (Utils.ceil32(arg.size) - arg.size)

        "#{size}#{arg}#{fill}".b
      elsif type.size.nil? # dynamic array type
        raise ArgumentError, "arg must be an array" unless arg.instance_of?(Array)

        head, tail = '', ''
        if type.dims.last == 0
          head += encode_type(Type.size_type, arg.size)
        else
          raise ArgumentError, "Wrong array size: found %d, expecting %d" % [arg.size, type.dims.last] unless arg.size == type.dims.last
        end

        sub_type = type.subtype
        sub_size = type.subtype.size
        arg.size.times do |i|
          if sub_size.nil?
            head += encode_type(Type.size_type, 32*arg.size + tail.size)
            tail += encode_type(sub_type, arg[i])
          else
            head += encode_type(sub_type, arg[i])
          end
        end

        "#{head}#{tail}".b
      else # static type
        if type.dims.empty?
          encode_primitive_type type, arg
        else
          arg.map {|x| encode_type(type.subtype, x) }.join.b
        end
      end
    end

    def encode_primitive_type(type, arg)
      # TODO
      "something".b
    end
  end

end
