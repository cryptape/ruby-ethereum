# -*- encoding : ascii-8bit -*-

require 'prime'

module Ethereum
  class Ethash

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
      def hashimoto_light(block_number, cache, header, nonce)
      end

      def hashimoto()
      end

    end

    def hashimoto_light(block_number, cache, header, nonce)
      lookup = ->(x) { calc_dateset_item(cache, x) }
      hashimoto header, nonce, get_full_size(block_number), lookup
    end

    def hashimoto(header, nonce, full_size, dataset_lookup)
      n = full_size / HASH_BYTES
      w = MIX_BYTES / WORD_BYTES
      mixhashes = MIX_BYTES / HASH_BYTES

      s = keccak512(header + nonce.reverse)

      mix = []
      mixhashes.times { mix.concat s }

      ACCESSES.times do |i|
        p = fnv(i ^ s[0], mix[i % w]) % (n / mixhashes) * mixhashes

        newdata = []
        mixhashes.times {|j| newdata.concat dataset_lookup(p + j) }
        mix = mix.zip(newdata).map {|(a,b)| fnv(a, b) }
      end

      cmix = []
      (mix.size / WORD_BYTES).times do |i|
        i *= WORD_BYTES
        cmix.push fnv(fnv(fnv(mix[i], mix[i+1]), mix[i+2]), mix[i+3])
      end

      { mixhash: serialize_hash(cmix),
        result: serialize_hash(keccak256(s + cmix)) }
    end

    def fnv(v1, v2)
      (v1 * FNV_PRIME ^ v2) % Constant::TT32
    end

    # sha3 hash function, outputs 64 bytes
    def keccak512(x)
      hash_words(x) do |v|
        Utils.keccak512(v)
      end
    end

    def keccak256(x)
      hash_words(x) do |v|
        Utils.keccak256(v)
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
      Utils.int_to_big_endian(i).reverse
    end

    # Assumes little endian bit ordering (same as Intel architectures)
    def decode_int(s)
      s && !s.empty? ? Utils.big_endian_to_int(s.reverse) : 0
    end

    def zpad(s, len)
      s + "\x00" * [0, len - s.size].max
    end

    def get_full_size(block_number)
      sz = DATASET_BYTES_INIT + DATASET_BYTES_GROWTH * (block_number / EPOCH_LENGTH)
      sz -= MIX_BYTES
      sz -= 2 * MIX_BYTES while !Prime.prime?(sz / MIX_BYTES)
      sz
    end

  end
end
