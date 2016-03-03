# -*- encoding : ascii-8bit -*-


module Ethereum
  module Ethash
    module Utils

      # sha3 hash function, outputs 64 bytes
      def keccak512(x)
        hash_words(x) do |v|
          Ethereum::Utils.keccak512(v)
        end
      end

      def keccak256(x)
        hash_words(x) do |v|
          Ethereum::Utils.keccak256(v)
        end
      end

      def hash_words(x, &block)
        x = serialize_hash(x) if x.instance_of?(Array)
        y = block.call(x)
        deserialize_hash(y)
      end

      def serialize_hash(h)
        h.map {|x| zpad(encode_int(x), WORD_BYTES) }.join
      end

      def deserialize_hash(h)
        (h.size / WORD_BYTES).times.map do |i|
          i *= WORD_BYTES
          decode_int h[i, WORD_BYTES]
        end
      end

      def encode_int(i)
        # `pack('L<`) will introduce leading zeros
        Ethereum::Utils.int_to_big_endian(i).reverse
      end

      # Assumes little endian bit ordering (same as Intel architectures)
      def decode_int(s)
        s && !s.empty? ? s.unpack('L<').first : 0
      end

      def zpad(s, len)
        s + "\x00" * [0, len - s.size].max
      end

    end
  end
end
