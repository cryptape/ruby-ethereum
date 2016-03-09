# -*- encoding : ascii-8bit -*-

module Ethereum
  class Miner

    class <<self
      def check_pow(block_number, header_hash, mixhash, nonce, difficulty)
        Logger.new('eth.miner').debug "checking pow",  block_number: block_number

        return false if mixhash.size != 32 || header_hash.size != 32 || nonce.size != 8

        cache = Ethash::Cache.get block_number
        mining_output = hashimoto_light block_number, cache, header_hash, nonce

        return false if mining_output[:mixhash] != mixhash
        return Utils.big_endian_to_int(mining_output[:result]) <= (Constant::TT256 / difficulty)
      end
      lru_cache :check_pow, 256

      def hashimoto_light(*args)
        # TODO: switch to ethhash c++ binding
        Ethash.hashimoto_light(*args)
      end
    end


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
    def initialize(block)
      @nonce = 0
      @block = block

      logger.debug "mining", block_number: @block.number, block_hash: Utils.encode_hex(@block.full_hash), block_difficulty: @block.difficulty
    end

    def mine(rounds=1000, start_nonce=0)
      blk = @block
      bin_nonce, mixhash = _mine(blk.number, blk.difficulty, blk.mining_hash, start_nonce, rounds)

      if bin_nonce.true?
        blk.mixhash = mixhash
        blk.nonce = bin_nonce
        return blk
      end
    end

    private

    def logger
      @logger ||= Logger.new 'eth.miner'
    end

    def _mine(block_number, difficulty, mining_hash, start_nonce=0, rounds=1000)
      raise AssertError, "start nonce must be an integer" unless start_nonce.is_a?(Integer)

      cache = Ethash::Cache.get block_number
      nonce = start_nonce
      difficulty ||= 1
      target = Utils.zpad Utils.int_to_big_endian(Constant::TT256 / difficulty), 32

      (1..rounds).each do |i|
        bin_nonce = Utils.zpad Utils.int_to_big_endian((nonce+i) & Constant::TT64M1), 8
        o = Miner.hashimoto_light block_number, cache, mining_hash, bin_nonce

        if o[:result] <= target
          logger.debug "nonce found"
          raise AssertError, "nonce must be 8 bytes long" unless bin_nonce.size == 8
          raise AssertError, "mishash must be 32 bytes long" unless o[:mixhash].size == 32
          return bin_nonce, o[:mixhash]
        end
      end

      return nil, nil
    end

  end
end
