module Ethereum

  ##
  # Mines on the current head. Stores received transactions.
  #
  # The process of finalising a block involves four stages:
  #
  # 1. validate (or, if mining, determine) uncles;
  # 2. validate (or, if mining, determine) transactions;
  # 3. apply rewards;
  # 4. verify (or, if mining, compute a valid) state and nonce.
  #
  class Miner

    class <<self
      # TODO: @lru_cache(maxsize=32)
      def check_pow(block_number, header_hash, mixhash, nonce, difficulty)
        logger.debug "checking pow block_number=#{block_number}"

        return false if mixhash.size != 32 || header_hash.size != 32 || nonce.size != 8

        cache = get_cache block_number
        mining_output = hashimoto_light block_number, cache, header_hash, nonce

        return false if mining_output[:mixhash] != mixhash
        return Utils.big_endian_to_int(mining_output[:result]) <= (2**256 / difficulty)
      end

      def hashimoto_light(*args)
        # TODO: switch to ethhash c++ binding
        Ethash.hashimoto_light(*args)
      end
    end

    ##
    # @param block [Block] the block for which to find a valid nonce
    #
    def initialize(block)
      #TODO
    end

  end

end
