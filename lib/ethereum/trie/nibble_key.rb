module Ethereum
  class Trie

    ##
    # Nibble is half-byte.
    #
    class NibbleKey < Array

      NIBBLE_TERM_FLAG  = 0b0010
      NIBBLE_ODD_FLAG   = 0b0001
      NIBBLE_TERMINATOR = 16

      HEX_VALUES = (0..15).inject({}) {|h, i| h[i.to_s(16).b] = i; h}.freeze

      class <<self
        ##
        # Encode nibbles to string.
        #
        # @see `pack_nibbles` in pyethereum
        #
        # @param nibbles [Array[Integer]] array of nibbles to encode
        #
        # @return [String] encoded string
        #
        def encode(nibbles)
          flags = 0

          if nibbles.last == NIBBLE_TERMINATOR
            flags |= NIBBLE_TERM_FLAG
            nibbles = nibbles[0...-1]
          end

          odd = nibbles.size % 2
          flags |= odd
          if odd == 1
            nibbles = [flags] + nibbles
          else
            nibbles = [flags, 0b0000] + nibbles
          end

          (nibbles.size/2).times.reduce('') do |s, i|
            base = 2*i
            s += (16*nibbles[base] + nibbles[base+1]).chr
          end
        end

        ##
        # Decode bytes to {NibbleKey}, with flags processed.
        #
        # @see `unpack_to_nibbles` in pyethereum
        #
        # @param bytes [String] compact hex encoded string.
        #
        # @return [NibbleKey] nibbles array, may have a terminator
        #
        def decode(bytes)
          o = from_string bytes
          flags = o[0]

          o.push NIBBLE_TERMINATOR if flags & NIBBLE_TERM_FLAG == 1

          fill = flags & NIBBLE_ODD_FLAG == 1 ? 1 : 2
          new o[fill..-1]
        end

        ##
        # Convert arbitrary string to {NibbleKey}.
        #
        # @see `bin_to_nibbles` in pyethereum
        #
        # @example
        #   from_string('') # => []
        #   from_string('h') # => [6, 8]
        #   from_string('he') # => [6, 8, 6, 5]
        #   from_string('hello') # => [6, 8, 6, 5, 6, 12, 6, 12, 6, 15]
        #
        # @param s [String] any string
        #
        # @return [NibbleKey] array of nibbles presented as interger smaller
        #   than 16, has no terminator because plain string has no flags
        #
        def from_string(s)
          nibbles = RLP::Utils.encode_hex(s).each_char.map {|nibble| HEX_VALUES[nibble] }
          new nibbles
        end

        ##
        # Convert {Array} of nibbles to {String}.
        #
        # @see `nibbles_to_bin` in pyethereum
        #
        # @param key [Array] array of nibbles
        #
        # @return [String] string represented by nibbles
        #
        def to_string(nibbles)
          raise ArgumentError, "nibbles can only be in 0..15" if nibbles.any? {|x| x > 15 || x < 0 }
          raise ArgumentError, "nibbles must be of even numbers" if nibbles.size % 2 == 1

          (nibbles.size/2).times.map do |i|
            base = i*2
            (16*nibbles[base] + nibbles[base+1]).chr
          end.join
        end

        def terminator
          new([NIBBLE_TERMINATOR])
        end
      end

      def initialize(*args)
        super
      end

      def terminate?
        last == NIBBLE_TERMINATOR
      end

      ##
      # Get with or without terminator copy of this {NibbleKey}.
      #
      # @param flag [Bool] set true to get a copy with terminator, otherwise
      #   set false
      #
      # @return [NibbleKey] a copy with or without terminator at end
      #
      def terminate(flag)
        dup.tap do |copy|
          if flag
            copy.push NIBBLE_TERMINATOR unless copy.terminate?
          else
            copy.pop if copy.terminate?
          end
        end
      end

      ##
      # test whether this is prefix of another {NibbleKey}
      #
      # @param another_key [NibbleKey] the full key to test
      #
      # @return [Bool]
      #
      def prefix?(another_key)
        return false if another_key.size < size
        another_key.take(size) == self
      end

      ##
      # Find common prefix to another key.
      #
      # @param another_key [Array] another array of nibbles
      #
      # @return [Array] common prefix of both nibbles array
      #
      def common_prefix(another_key)
        prefix = []

        [size, another_key.size].min.times do |i|
          break if self[i] != another_key[i]
          prefix.push self[i]
        end

        self.class.new prefix
      end

      def encode
        self.class.encode self
      end

      def to_string
        self.class.to_string self
      end
    end

  end
end
