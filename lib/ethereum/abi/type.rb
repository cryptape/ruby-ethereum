module Ethereum
  module ABI
    class Type

      class ParseError < StandardError; end

      class <<self
        ##
        # Crazy regexp to seperate out base type component (eg. uint), size (eg.
        # 256, 128x128, nil), array component (eg. [], [45], nil)
        #
        def parse(type)
          _, base, sub, dimension = /([a-z]*)([0-9]*x?[0-9]*)((\[[0-9]*\])*)/.match(type).to_a

          dims = dimension.scan(/\[[0-9]*\]/)
          raise ParseError, "Unknown characters found in array declaration" if dims.join != dimension

          case base
          when 'string'
            raise ParseError, "String type must have no suffix or numerical suffix" unless sub.empty?
          when 'bytes'
            raise ParseError, "Maximum 32 bytes for fixed-length string or bytes" unless sub.empty? || sub.to_i <= 32
          when 'uint', 'int'
            raise ParseError, "Integer type must have numerical suffix" unless sub =~ /^[0-9]+$/

            size = sub.to_i
            raise ParseError, "Integer size out of bounds" unless size >= 8 && size <= 256
            raise ParseError, "Integer size must be multiple of 8" unless size % 8 == 0
          when 'ureal', 'real', 'fixed', 'ufixed'
            raise ParseError, "Real type must have suffix of form <high>x<low>, e.g. 128x128" unless sub =~ /^[0-9]+x[0-9]+$/

            high, low = sub.split('x').map(&:to_i)
            total = high + low

            raise ParseError, "Real size out of bounds (max 32 bytes)" unless total >= 8 && total <= 256
            raise ParseError, "Real high/low sizes must be multiples of 8" unless high % 8 == 0 && low % 8 == 0
          when 'hash'
            raise ParseError, "Hash type must have numerical suffix" unless sub =~ /^[0-9]+$/
          when 'address'
            raise ParseError, "Address cannot have suffix" unless sub.empty?
          when 'bool'
            raise ParseError, "Bool cannot have suffix" unless sub.empty?
          else
            raise ParseError, "Unrecognized type base: #{base}"
          end

          new(base, sub, dims.map {|x| x[1...-1].to_i })
        end
      end

      attr :base, :sub, :dims

      ##
      # @param base [String] base name of type, e.g. uint for uint256[4]
      # @param sub  [String] subscript of type, e.g. 256 for uint256[4]
      # @param dims [Array[Integer]] dimensions of array type, e.g. [1,2,0]
      #   for uint256[1][2][], [] for non-array type
      #
      def initialize(base, sub, dims)
        @base = base
        @sub  = sub
        @dims = dims
      end

      def ==(another_type)
        base == another_type.base &&
          sub == another_type.sub &&
          dims == another_type.dims
      end

      ##
      # Get the static size of a type, or nil if dynamic.
      #
      # @return [Integer, NilClass]  size of static type, or nil for dynamic
      #   type
      #
      def size
        if dims.empty?
          return nil if %w(string bytes).include?(base) && sub.empty?
          return 32
        end

        return nil if dims.last == 0 # 0 for dynamic array []

        sub_size = self.class.new(base, sub, dims[0...-1]).size
        sub_size.nil? ? nil : dims.last*sub_size
      end
    end
  end
end
