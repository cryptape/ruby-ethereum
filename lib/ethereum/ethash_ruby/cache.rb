# -*- encoding : ascii-8bit -*-

require 'prime'

module Ethereum
  module EthashRuby

    class Cache
      include Utils

      CACHE_BY_SEED_MAX = 10

      class <<self
        def seeds
          @seeds ||= ["\x00"*32]
        end

        def cache_by_seed
          @cache_by_seed ||= {} # ordered hash
        end

        def cache_by_file(block_number, data=nil)
          path = "/tmp/ruby_ethereum_hashimoto_cache_#{block_number}"
          if data
            File.open(path, 'wb') {|f| f.write Marshal.dump(data) }
          else
            if File.exist?(path)
              File.open(path, 'rb') {|f| Marshal.load f.read }
            else
              nil
            end
          end
        end

        def get_seed(block_number)
          epoch_no = block_number / EPOCH_LENGTH
          while seeds.size <= epoch_no
            seeds.push Ethereum::Utils.keccak256(seeds.last)
          end

          seeds[epoch_no]
        end

        def get(block_number)
          seed = get_seed block_number

          if cache_by_seed.has_key?(seed)
            c = cache_by_seed.delete seed # pop
            cache_by_seed[seed] = c # and append at end
            return c
          end

          if c = cache_by_file(block_number)
            cache_by_seed[seed] = c
            return c
          end

          new(block_number).to_a.tap do |c|
            cache_by_seed[seed] = c
            cache_by_file block_number, c
            if cache_by_seed.size > CACHE_BY_SEED_MAX
              cache_by_seed.delete cache_by_seed.keys.first # remove last recently accessed
            end
          end
        end
        lru_cache :get, 16
      end

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
