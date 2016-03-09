# -*- encoding : ascii-8bit -*-

require 'test_helper'

class ChainTest < Minitest::Test
  include Ethereum

  def setup
    @db = DB::EphemDB.new
    @env = Env.new @db

    k = Utils.keccak256('cow')
    v = PrivateKey.new(k).to_address
    k2 = Utils.keccak256('horse')
    v2 = PrivateKey.new(k2).to_address

    @accounts = [k,v,k2,v2]
  end

  def test_mining
    blk = mkgenesis db: @db
    assert_equal 0, blk.number
    assert_equal 1, blk.difficulty

    2.times do |i|
      blk = mine_next_block blk
      assert_equal i+1, blk.number
    end
  end

  private

  def mkgenesis(initial_alloc: {}, db: nil)
    assert db

    o = Block.genesis Env.new(db), start_alloc: initial_alloc, difficulty: 1
    assert_equal 1, o.difficulty

    o
  end

  ##
  # Mine the next block on a chain.
  #
  # The newly mined block will be considered to be the head of the chain,
  # regardless of its total dificulty.
  #
  # @param parent [Block] the parent of the block to mine, or `nil` to use the
  #   current chain head
  # @param transactions [Array[Transaction]] a list of transactions to include
  #   in the new block
  # @param coinbase [String] optional coinbase to replace `chain.coinbase`
  #
  def mine_on_chain(chain, parent=nil, transactions=[], coinbase=nil)
    parent ||= chain.head
    chain.coinbase = coinbase if coinbase

    chain.update_head parent
    transactions.each {|t| chain.add_transaction t }
    assert_equal 1, chain.head_candidate.difficulty

    m = Miner.new chain.head_candidate
    rounds = 100
    nonce = 0

    b = nil
    loop do
      b = m.mine(rounds, nonce)
      break if b
      nonce += rounds
    end

    assert b.header.check_pow
    chain.add_block b
    b
  end

  def mine_next_block(parent, coinbase=nil, transactions=[])
    if coinbase.true?
      c = Chain.new parent.env, genesis: parent, coinbase: coinbase
    else
      c = Chain.new parent.env, genesis: parent
    end

    transactions.each {|tx| c.add_transaction tx }

    mine_on_chain c
  end

  def get_transaction(gasprice=0, nonce=0)
    k, v, k2, v2 = @accounts
    Transaction.new(
      nonce: nonce,
      gasprice: gasprice,
      startgas: 100000,
      to: v2,
      value: 10.finney,
      data: ''
    ).sign(k)
  end

end
