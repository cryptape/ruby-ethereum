# -*- encoding : ascii-8bit -*-

require 'ethash'
require 'ethereum/ethash_ruby'

module Ethereum
  module Ethash

    class <<self
      def get_cache(blknum)
        ::Ethash.mkcache_bytes blknum
      end

      def hashimoto_light(blknum, cache, mining_hash, bin_nonce)
        nonce = Utils.big_endian_to_int(bin_nonce)
        ::Ethash.hashimoto_light blknum, cache, mining_hash, nonce
      end
    end

  end
end
