# -*- encoding : ascii-8bit -*-

require 'ethash'
require 'ethereum/ethash_ruby'

module Ethereum
  module Ethash

    EPOCH_LENGTH = ::Ethash::EPOCH_LENGTH

    CACHE_BY_SEED_MAX = 32

    class <<self
      def seeds
        @seeds ||= ["\x00"*32]
      end

      def get_seed(block_number)
        epoch_no = block_number / EPOCH_LENGTH
        while seeds.size <= epoch_no
          seeds.push Ethereum::Utils.keccak256(seeds.last)
        end

        seeds[epoch_no]
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

      def get_cache(blknum)
        seed = get_seed blknum

        if cache_by_seed.has_key?(seed)
          c = cache_by_seed.delete seed # pop
          cache_by_seed[seed] = c # and append at end
          return c
        end

        if c = cache_by_file(Utils.encode_hex(seed))
          cache_by_seed[seed] = c
          return c
        end

        # Use c++ implementation or ethash_ruby
        c = ::Ethash.mkcache_bytes blknum
        #c = EthashRuby::Cache.new(blknum).to_a

        cache_by_seed[seed] = c
        cache_by_file Utils.encode_hex(seed), c
        if cache_by_seed.size > CACHE_BY_SEED_MAX
          cache_by_seed.delete cache_by_seed.keys.first # remove last recently accessed
        end

        c
      end

      def hashimoto_light(blknum, cache, mining_hash, bin_nonce)
        nonce = Utils.big_endian_to_int(bin_nonce)
        ::Ethash.hashimoto_light blknum, cache, mining_hash, nonce
      end
    end

  end
end
