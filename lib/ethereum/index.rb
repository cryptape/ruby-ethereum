# -*- encoding : ascii-8bit -*-

module Ethereum

  ##
  # Collection of indexes.
  #
  # * children - needed to get the uncles of a block
  # * blocknumbers - needed to mark the longest chain (path to top)
  # * transactions - optional to resolve txhash to block:tx
  #
  class Index

    def initialize(env, index_transactions=true)
      @env = env
      @db = env.db
      @index_transactions = index_transactions
    end

    def add_block(blk)
      add_child blk.prevhash, blk.full_hash
      add_transactions blk if @index_transactions
    end

    def add_child(parent_hash, child_hash)
      children = (get_children(parent_hash) + [child_hash]).uniq
      @db.put_temporarily child_db_key(parent_hash), RLP.encode(children)
    end

    # start from head and update until the existing indices match the block
    def update_blocknumbers(blk)
      loop do
        if blk.number > 0
          @db.put_temporarily block_by_number_key(blk.number), blk.full_hash
        else
          @db.put block_by_number_key(blk.number), blk.full_hash
        end
        @db.commit_refcount_changes blk.number

        break if blk.number == 0

        blk = blk.get_parent()
        break if has_block_by_number(blk.number) && get_block_by_number(blk.number) == blk.full_hash
      end
    end

    def has_block_by_number(number)
      @db.has_key? block_by_number_key(number)
    end

    def get_block_by_number(number)
      @db.get block_by_number_key(number)
    end

    def get_children(blk_hash)
      key = child_db_key blk_hash
      @db.has_key?(key) ? RLP.decode(@db.get(key)) : []
    end

    ##
    # @param txhash [String] transaction hash
    #
    # @return [[Transaction, Block, Integer]] transaction, block, and tx number
    #
    def get_transaction(txhash)
      blockhash, tx_num_enc = RLP.decode @db.get(txhash)
      blk = RLP.decode(@db.get(blockhash), sedes: Block, env: @env)

      num = Utils.decode_int tx_num_enc
      tx_data = blk.get_transaction num

      [tx_data, blk, num]
    end

    private

    def child_db_key(blk_hash)
      "ci:#{blk_hash}"
    end

    def add_transactions(blk)
      blk.get_transactions.each_with_index do |tx, i|
        @db.put_temporarily tx.full_hash, RLP.encode([blk.full_hash, i])
      end

      @db.commit_refcount_changes blk.number
    end

    def block_by_number_key(number)
      "blocknumber:#{number}"
    end

  end

end
