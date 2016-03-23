# -*- encoding : ascii-8bit -*-

require 'prime'

module Ethereum
  module EthashRuby

    class Cache
      include Utils

      def initialize(block_number)
        @block_number = block_number
      end

      def to_a
        n = size / HASH_BYTES

        o = [keccak512(seed)]
        (1...n).each {|i| o.push keccak512(o.last) }

        CACHE_ROUNDS.times do
          n.times do |i|
            v = o[i][0] % n
            xor = o[(i-1+n) % n].zip(o[v]).map {|(a,b)| a^b }
            o[i] = keccak512 xor
          end
        end

        o
      end

      def seed
        @seed ||= self.class.get_seed(@block_number)
      end

      def size
        sz = CACHE_BYTES_INIT + CACHE_BYTES_GROWTH * (@block_number / EPOCH_LENGTH)
        sz -= HASH_BYTES

        sz -= 2 * HASH_BYTES while !Prime.prime?(sz / HASH_BYTES)
        sz
      end

    end

  end
end
