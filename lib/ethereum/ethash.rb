# -*- encoding : ascii-8bit -*-

require 'ethereum/ethash/utils'
require 'ethereum/ethash/cache'
require 'ethereum/ethash/hashimoto'

module Ethereum
  module Ethash

    EPOCH_LENGTH = 30000         # blocks per epoch
    ACCESSES = 64                # number of accesses in hashimoto loop

    DATASET_BYTES_INIT = 2**30   # bytes in dataset at genesis
    DATASET_BYTES_GROWTH = 2**23 # growth per epoch (~ 7GB per year)
    DATASET_PARENTS = 256        # number of parents of each dataset element

    CACHE_BYTES_INIT = 2**24     # size of the dataset relative to the cache
    CACHE_BYTES_GROWTH = 2**17   # size of the dataset relative to the cache
    CACHE_ROUNDS = 3             # number of rounds in cache production

    WORD_BYTES = 4               # bytes in word
    MIX_BYTES = 128              # width of mix
    HASH_BYTES = 64              # hash length in bytes

    FNV_PRIME = 0x01000193

    class <<self
      def hashimoto_light(*args)
        Hashimoto.new.light(*args)
      end
    end

  end
end
