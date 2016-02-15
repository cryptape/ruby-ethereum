module Ethereum

  ##
  # Manages the chain and requests to it.
  #
  class Chain

    HEAD_KEY = 'HEAD'.freeze

    ##
    # @param config [Ethereum::Config] configuration of the chain
    #
    def initialize(config, genesis: nil, new_head_cb: nil, coinbase: Constant::ADDRESS_ZERO)
      @config = config
      @db = config.db
      @new_head_cb = new_head_cb
      @index = Index.new config
      @coinbase = coinbase

      initialize_blockchain(genesis) unless @db.has_key?(HEAD_KEY)
      logger.debug "chain @ head_hash=#{head}"

      @genesis = get @index.get_block_by_number(0)
      logger.debug "got genesis nonce=#{Utils.encode_hex @genesis.nonce} difficulty=#{@genesis.difficulty}"

      @head_candidate = nil
      update_head_candidate
    end

    def head
      initialize_blockchain unless @db && @db.has_key?(HEAD_KEY)
      ptr = @db.get HEAD_KEY
      blocks.get_block @config, ptr # TODO - blocks
    end

    def commit
      #TODO
    end

    def include?(blk_hash)
      # TODO
    end

    private

    def logger
      @logger = Logger['eth.chain']
    end

    def initialize_blockchain(genesis=nil)
      logger.info "Initializing new chain"

      unless genesis
        genesis = blocks.genesis @config # TODO - blocks
        logger.info "new genesis genesis_hash=#{genesis} difficulty=#{genesis.difficulty}"
        @index.add_block genesis
      end

      store_block genesis
      raise "failed to store block" unless genesis == blocks.get_block(@config, genesis.hash)

      update_head genesis
      raise "falied to update head" unless include?(genesis.hash)

      commit
    end

    def store_block
      # TODO
    end

    def update_head_candidate
      # TODO
    end

  end
end
