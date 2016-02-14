require 'ethereum/abi/type'

module Ethereum

  ##
  # Contract ABI encoding and decoding.
  #
  # @see https://github.com/ethereum/wiki/wiki/Ethereum-Contract-ABI
  #
  module ABI

    extend self

    class EncodingError < StandardError; end
    class ValueOutOfBounds < StandardError; end

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
        padding = Utils::ZERO_BYTE * (Utils.ceil32(arg.size) - arg.size)

        "#{size}#{arg}#{padding}".b
      elsif type.size.nil? # dynamic array type
        raise ArgumentError, "arg must be an array" unless arg.instance_of?(Array)

        head, tail = '', ''
        if type.dims.last == 0
          head += encode_type(Type.size_type, arg.size)
        else
          raise ArgumentError, "Wrong array size: found #{arg.size}, expecting #{type.dims.last}" unless arg.size == type.dims.last
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
      case type.base
      when 'uint'
        real_size = type.sub.to_i
        i = decode_integer arg

        raise ValueOutOfBounds, arg unless i >= 0 && i < 2**real_size
        Utils.zpad_int i
      when 'bool'
        raise ArgumentError, "arg is not bool: #{arg}" unless arg.instance_of?(TrueClass) || arg.instance_of?(FalseClass)
        Utils.zpad_int(arg ? 1: 0)
      when 'int'
        real_size = type.sub.to_i
        i = decode_integer arg

        raise ValueOutOfBounds, arg unless i >= -2**(real_size-1) && i < 2**(real_size-1)
        Utils.zpad_int(i % 2**sub)
      when 'ureal', 'ufixed'
        high, low = type.sub.split('x').map(&:to_i)

        raise ValueOutOfBounds, arg unless arg >= 0 && arg < 2**high
        Utils.zpad_int(arg * 2**low)
      when 'real', 'fixed'
        high, low = type.sub.split('x').map(&:to_i)

        raise ValueOutOfBounds, arg unless arg >= -2**(high - 1) && arg < 2**(high - 1)
        Utils.zpad_int((arg % 2**high) * 2**low)
      when 'string', 'bytes'
        raise EncodingError, "Expecting string: #{arg}" unless arg.instance_of?(String)

        if type.sub.empty? # variable length type
          size = zpad Utils.encode_int(arg.size), 32
          padding = Utils::ZERO_BYTE * (Utils.ceil32(arg.size) - arg.size)
          "#{size}#{arg}#{padding}".b
        else # fixed length type
          raise ValueOutOfBounds, arg unless arg.size <= type.sub.to_i

          padding = Utils::ZERO_BYTE * (32 - arg.size)
          "#{arg}#{padding}".b
        end
      when 'hash'
        size = type.sub.to_i
        raise EncodingError, "too long: #{arg}" unless size > 0 && size <= 32

        if arg.is_a?(Integer)
          Utils.zpad_int(arg)
        elsif arg.size == size
          Utils.zpad arg, 32
        elsif arg.size == size * 2
          Utils.zpad RLP::Utils.decode_hex(arg), 32
        else
          raise EncodingError, "Could not parse hash: #{arg}"
        end
      when 'address'
        if arg.is_a?(Integer)
          Utils.zpad_int arg
        elsif arg.size == 20
          Utils.zpad arg, 32
        elsif arg.size == 40
          Utils.zpad RLP::Utils.decode_hex(arg), 32
        elsif arg.size == 42 && arg[0,2] == '0x'
          Utils.zpad RLP::Utils.decode_hex(arg[2..-1]), 32
        else
          raise EncodingError, "Could not parse address: #{arg}"
        end
      else
        raise EncodingError, "Unhandled type: #{type.base} #{type.sub}"
      end
    end

    ##
    # Decodes multiple arguments using the head/tail mechanism.
    #
    def decode(types, data)
      parsed_types = types.map {|t| Type.parse(t) }

      outputs = [nil] * types.size
      start_positions = [nil] * types.size + [data.size]

      # TODO: refactor, a reverse iteration will be better
      pos = 0
      parsed_types.each_with_index do |t, i|
        # If a type is static, grab the data directly, otherwise record its
        # start position
        if t.size # not nil, static type
          outputs[i] = data[pos, t.size]
          pos += t.size
        else # dynamic type
          start_positions[i] = Utils.big_endian_to_int(data[pos, 32])

          j = i - 1
          while j >= 0 && start_positions[j].nil?
            start_positions[j] = start_positions[i]
            j -= 1
          end

          pos += 32
        end
      end

      # We add a start position equal to the length of the entire data for
      # convenience.
      j = types.size - 1
      while j >= 0 && start_positions[j].nil?
        start_positions[j] = start_positions[types.size]
        j -= 1
      end

      raise ArgumentError, "Not enough data for head" unless pos <= data.size

      parsed_types.each_with_index do |t, i|
        if t.size.nil?
          offset, next_offset = start_positions[i, 2]
          outputs[i] = data[offset...next_offset]
        end
      end

      parsed_types.zip(outputs).map {|(type, out)| decode_type(type, out) }
    end

    def decode_type(type, arg)

    end

    private

    def decode_integer(n)
      case n
      when Integer
        raise EncodingError, "Number out of range: #{n}" if n > INT_MAX || n < INT_MIN
        n
      when String
        if n.size == 40
          Utils.big_endian_to_int RLP::Utils.decode_hex(n)
        elsif n.size <= 32
          Utils.big_endian_to_int n
        else
          raise EncodingError, "String too long: #{n}"
        end
      when true
        1
      when false, nil
        0
      else
        raise EncodingError, "Cannot decode integer: #{n}"
      end
    end

  end

end
