# -*- encoding : ascii-8bit -*-

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
      raise ArgumentError, "env must be instance of Env" unless env.instance_of?(Env)

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
      Block.find @env, ptr
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
        genesis = Block.genesis(@env)
        logger.info "new genesis", genesis_hash: genesis, difficulty: genesis.difficulty
        @index.add_block genesis
      end

      store_block genesis
      raise "failed to store block" unless genesis == Block.find(@env, genesis.full_hash)

      update_head genesis
      raise "falied to update head" unless include?(genesis.full_hash)

      commit
    end

    def store_block(block)
      if block.number > 0
        @db.put_temporarily block.hash, RLP.encode(block)
      else
        @db.put block.hash, RLP.encode(block)
      end
    end

    def update_head(block, forward_pending_transaction=true)
      logger.debug "updating head"
      logger.debug "New Head is on a different branch", head_hash: block, old_head_hash: head if !block.genesis? && block.get_parent != head

      # Some temporary auditing to make sure pruning is working well
      if block.number > 0 && block.number % 500 == 0 && @db.instance_of?(DB::RefcountDB)
        # TODO
      end

      # Fork detected, revert death row and change logs
      if block.number > 0
        b = block.get_parent
        h = head
        b_children = []

        if b.full_hash != h.full_hash
          logger.warn "reverting"

          while h.number > b.number
            h.db.revert_refcount_changes h.number
            h = h.get_parent
          end
          while b.number > h.number
            b_children.push b
            b = b.get_parent
          end

          while b.full_hash != h.full_hash
            h.db.revert_refcount_changes h.number
            h = h.get_parent

            b_children.push b
            b = b.get_parent
          end

          b_children.each do |bc|
            Block.verify(bc, bc.get_parent)
          end
        end
      end

      @db.put HEAD_KEY, block.full_hash
      raise "Chain write error!" unless @db.get(HEAD_KEY) == block.full_hash

      @index.update_blocknumbers(head)
      raise "Fail to update head!" unless head == block

      logger.debug "set new head", head: head
      update_head_candidate forward_pending_transaction

      @new_head_cb.call(block) if @new_head_cb && !block.genesis?
    end

    # after new head is set
    def update_head_candidate(forward_pending_transaction=true)
      logger.debug "updating head candidate", head: head

      # collect uncles
      blk = head # parent of the block we are collecting uncles for
      uncles = get_brothers(blk).map(&:header).uniq

      (@env.config[:max_uncle_depth]+2).times do |i|
        blk.uncles.each {|u| uncles.delete u }
        blk = blk.get_parent if blk.has_parent?
      end

      raise "strange uncle found!" unless uncles.empty? || uncles.map(&:number).max <= head.number

      uncles = uncles[0, @env.config[:max_uncles]]

      # create block
      ts = [Time.now.to_i, head.timestamp+1].max
      _env = Env.new OverlayDB.new(head.db), @env.config, @env.global_config
      head_candidate = Block.build_from_parent head, @coinbase, timestamp: ts, uncles: uncles, env: _env
      raise ValidationError, "invalid uncles" unless head_candidate.validate_uncles

      @pre_finalize_state_root = head_candidate.state_root
      head_candidate.finalize

      # add transactions from previous head candidate
      old_head_candidate = @head_candidate
      @head_candidate = head_candidate

      if old_head_candidate
        tx_hashes = head.get_transaction_hashes
        pending = old_head_candidate.get_transactions.select {|tx| !tx_hashes.include?(tx.full_hash) }

        if pending.true?
          if forward_pending_transaction
            logger.debug "forwarding pending transaction", num: pending.size
            pending.each {|tx| add_transaction tx }
          else
            logger.debug "discarding pending transaction", num: pending.size
          end
        end
      end
    end

    def get_brothers(blk)
      #TODO
    end

  end
end
