module Ethereum

  ###
  # Blooms are the 3-point, 2048-bit (11-bits/point) Bloom filter of each
  # component (except data) of each log entry of each transation.
  #
  # We set the bits of a 2048-bit value whose indices are given by the low
  # order 9-bits of the first three double-bytes of the SHA3 of each value.
  #
  # @example
  #   bloom(0f572e5295c57f15886f9b263e2f6d2d6c7b5ec6)
  #   sha3: bd2b01afcd27800b54d2179edc49e2bffde5078bb6d0b204694169b1643fb108
  #   first 3 double-bytes: bd2b, 01af, cd27
  #   bits in bloom: 1323, 431, 1319
  #
  # Blooms are type of `Integer`.
  #
  class Bloom

    BITS = 2048
    MASK = 2047
    BUCKETS = 3

    class <<self
      def from(v)
        insert(0, v)
      end

      def from_array(args)
        blooms = args.map {|arg| from(arg) }
        combine *blooms
      end

      def insert(bloom, v)
        h = Utils.keccak_256 v
        BUCKETS.times {|i| bloom |= get_index(h, i) }
        bloom
      end

      def query(bloom, v)
        b = from v
        (bloom & b) == b
      end

      def combine(*args)
        args.reduce(&:|)
      end

      def bits(v)
        h = Utils.keccak_256 v
        BUCKETS.times.map {|i| bits_in_number get_index(h, i) }
      end

      def bits_in_number(v)
        BITS.times.select {|i| (1<<i) & v > 0 }
      end

      def b256(int_bloom)
        Utils.zpad Utils.int_to_big_endian(int_bloom), 256
      end

      ##
      # Get index for hash double-byte in bloom.
      #
      # @param hash [String] value hash
      # @param pos [Integer] double-byte position in hash, can only be 0, 1, 2
      #
      # @return [Integer] bloom index
      #
      def get_index(hash, pos)
        raise ArgumentError, "invalid double-byte position" unless [0,1,2].include?(pos)

        i = pos*2
        hi = hash[i].ord << 8
        lo = hash[i+1].ord
        1 << ((hi+lo) & MASK)
      end

    end
  end
end
