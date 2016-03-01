# -*- encoding : ascii-8bit -*-

require 'set'

module Ethereum

  ##
  # Manages the chain and requests to it.
  #
  class Chain

    HEAD_KEY = 'HEAD'.freeze

    ##
    # @param env [Ethereum::Env] configuration of the chain
    #
    def initialize(env, genesis: nil, new_head_cb: nil, coinbase: Address::ZERO)
      @env = env
      @db = env.db
      @new_head_cb = new_head_cb
      @index = Index.new env
      @coinbase = coinbase

      initialize_blockchain(genesis) unless @db.has_key?(HEAD_KEY)
      logger.debug "chain @ head_hash=#{head}"

      @genesis = get @index.get_block_by_number(0)
      logger.debug "got genesis", nonce: Utils.encode_hex(@genesis.nonce), difficulty: @genesis.difficulty

      @head_candidate = nil
      update_head_candidate
    end

    def head
      initialize_blockchain unless @db && @db.has_key?(HEAD_KEY)
      ptr = @db.get HEAD_KEY
      blocks.get_block @env, ptr # TODO - blocks
    end

    def commit
      @db.commit
    end

    def include?(blk_hash)
      @db.has_key?(blk_hash)
    end

    private

    def logger
      @logger ||= Logger.new 'eth.chain'
    end

    def initialize_blockchain(genesis=nil)
      logger.info "Initializing new chain"

      unless genesis
        genesis = blocks.genesis @env # TODO - blocks
        logger.info "new genesis", genesis_hash: genesis, difficulty: genesis.difficulty
        @index.add_block genesis
      end

      store_block genesis
      raise "failed to store block" unless genesis == blocks.get_block(@env, genesis.hash)

      update_head genesis
      raise "falied to update head" unless include?(genesis.hash)

      commit
    end

    def store_block(block)
      if block.number > 0
        @db.put_temporarily block.hash, RLP.encode(block)
      else
        @db.put block.hash, RLP.encode(block)
      end
    end

    def update_head_candidate(forward_pending_transaction=true)
      logger.debug "updating head candidate", head: head

      current_blk = head_blk = head # parent of the block we are collecting uncles for
      uncles = Set.new get_brothers(current_blk).map(&:header)

      (@env.config[:max_uncle_depth]+1).times do |i|
        current_blk.uncles.each {|u| uncles.remove u }
        current_blk = current_blk.get_parent if current_blk.has_parent
      end

      raise "strange uncle found!" unless uncles.empty? || uncles.map(&:number).max <= head_blk.number

      uncles = uncles.to_a[0, @env.config[:max_uncles]]

      # create block
      ts = [Time.now.to_i, head_blk.timestamp+1].max
      _env = Env.new OverlayDB.new(head_blk.db), @env.config, @env.global_config #TODO: overlaydb
      @head_candidate = blocks.Block.init_from_parent head_blk, coinbase: @coinbase, timestamp: ts, uncles: uncles, env: _env



    end

    def get_brothers(blk)
      #TODO
    end

  end
end
