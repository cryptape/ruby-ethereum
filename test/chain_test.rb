# -*- encoding : ascii-8bit -*-

require 'test_helper'

class ChainTest < Minitest::Test
  include Ethereum

  def setup
    @db = DB::EphemDB.new
    @env = Env.new @db

    @k = Utils.keccak256('cow')
    @v = PrivateKey.new(@k).to_address
    @k2 = Utils.keccak256('horse')
    @v2 = PrivateKey.new(@k2).to_address

    @accounts = [@k,@v,@k2,@v2]
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

  def test_transfer
    blk = Block.genesis @env, start_alloc: {@v => {balance: 1.ether}}

    b_v = blk.get_balance @v
    b_v2 = blk.get_balance @v2
    value = 42

    success = blk.transfer_value @v, @v2, value
    assert_equal true, success
    assert_equal b_v-value, blk.get_balance(@v)
    assert_equal b_v2+value, blk.get_balance(@v2)
  end

  def test_failing_transfer
    blk = Block.genesis @env, start_alloc: {@v => {balance: 1.ether}}

    b_v = blk.get_balance @v
    b_v2 = blk.get_balance @v2
    value = 2.ether

    success = blk.transfer_value @v, @v2, value
    assert_equal false, success
    assert_equal b_v, blk.get_balance(@v)
    assert_equal b_v2, blk.get_balance(@v2)
  end

  def test_serialize_block
    blk = Block.genesis @env
    tb_blk = BlockHeader.from_block_rlp RLP.encode(blk)

    assert_equal blk.full_hash, tb_blk.full_hash
    assert_equal blk.number, tb_blk.number
  end

  def test_genesis
    blk = Block.genesis Env.new(@db), start_alloc: {@v => {balance: 1.ether}}
    assert_equal @db.db, blk.state.db.db

    @db.put blk.full_hash, RLP.encode(blk)
    blk.state.db.commit
    @db.commit

    blk2 = Block.genesis Env.new(@db), start_alloc: {@v => {balance: 1.ether}}
    blk3 = Block.genesis Env.new(@db)
    assert blk == blk2
    assert blk != blk3

    alt_db = DB::EphemDB.new
    blk2 = Block.genesis Env.new(alt_db), start_alloc: {@v => {balance: 1.ether}}
    blk3 = Block.genesis Env.new(alt_db)
    assert blk == blk2
    assert blk != blk3
  end

  def test_deserialize
    blk = Block.genesis @env
    @db.put blk.full_hash, RLP.encode(blk)
    assert_equal blk, Block.find(@env, blk.full_hash)
  end

  def test_deserialize_commit
    blk = Block.genesis @env
    @db.put blk.full_hash, RLP.encode(blk)
    @db.commit
    assert_equal blk, Block.find(@env, blk.full_hash)
  end

  def test_genesis_db
    blk = Block.genesis Env.new(@db), start_alloc: {@v => {balance: 1.ether}}
    store_block blk

    blk2 = Block.genesis Env.new(@db), start_alloc: {@v => {balance: 1.ether}}
    blk3 = Block.genesis Env.new(@db)
    assert blk == blk2
    assert blk != blk3

    alt_db = DB::EphemDB.new
    blk2 = Block.genesis Env.new(alt_db), start_alloc: {@v => {balance: 1.ether}}
    blk3 = Block.genesis Env.new(alt_db)
    assert blk == blk2
    assert blk != blk3
  end

  def test_mine_block
    blk = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: @db
    store_block blk

    blk2 = mine_next_block blk, coinbase: @v
    store_block blk

    assert_equal @env.config[:block_reward] + blk.get_balance(@v), blk2.get_balance(@v)
    assert_equal blk.state.db.db, blk2.state.db.db.db
    assert_equal blk, blk2.get_parent
  end

  def test_block_serialization_with_transaction_empty_genesis
    blk = mkgenesis db: @db
    store_block blk

    tx = get_transaction gasprice: 10
    blk2 = mine_next_block(blk, transactions: [tx])

    assert !blk2.get_transactions.include?(tx)
    assert_raises(IndexError) { blk2.get_transaction(0) }
  end

  def test_mine_block_with_transaction
    blk = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: @db
    store_block blk

    tx = get_transaction
    blk = mine_next_block blk, transactions: [tx]

    assert blk.get_transactions.include?(tx)
    assert_equal tx, blk.get_transaction(0)
    assert_raises(IndexError) { blk.get_transaction(1) }
    assert_equal 990.finney, blk.get_balance(@v)
    assert_equal 10.finney, blk.get_balance(@v2)
  end

  def test_mine_block_with_transaction2
    blk = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: @db
    store_block blk

    tx = get_transaction
    blk2 = mine_next_block blk, coinbase: @v, transactions: [tx]
    store_block blk2

    assert_equal blk2, Block.find(Env.new(blk2.db), blk2.full_hash)
    assert_equal 0, tx.gasprice
    assert_equal @env.config[:block_reward] + blk.get_balance(@v) - tx.value, blk2.get_balance(@v)
    assert_equal blk.state.db.db, blk2.state.db.db.db
    assert_equal blk, blk2.get_parent
    assert blk2.get_transactions.include?(tx)
    assert !blk.get_transactions.include?(tx)
  end

  def test_block_serialization_same_db
    blk = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: @db
    assert_equal RLP.decode(RLP.encode(blk), sedes: Block, env: Env.new(@db)).full_hash, blk.full_hash
    store_block blk

    blk2 = mine_next_block blk
    assert_equal RLP.decode(RLP.encode(blk), sedes: Block, env: Env.new(@db)).full_hash, blk.full_hash
    assert_equal RLP.decode(RLP.encode(blk2), sedes: Block, env: Env.new(@db)).full_hash, blk2.full_hash
  end

  def test_block_serialization_other_db
    a_db, b_db = DB::EphemDB.new, DB::EphemDB.new

    a_blk = mkgenesis db: a_db
    store_block a_blk
    a_blk2 = mine_next_block a_blk
    store_block a_blk2

    b_blk = mkgenesis db: b_db
    assert_equal a_blk, b_blk
    store_block b_blk

    b_blk2 = RLP.decode RLP.encode(a_blk2), sedes: Block, env: Env.new(b_blk.db)
    assert_equal a_blk2.full_hash, b_blk2.full_hash
    store_block(b_blk2)
    assert_equal a_blk2.full_hash, b_blk2.full_hash
  end

  def test_block_serialization_with_transaction_other_db
    a_db, b_db = DB::EphemDB.new, DB::EphemDB.new

    a_blk = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: a_db
    store_block a_blk

    tx = get_transaction
    a_blk2 = mine_next_block a_blk, transactions: [tx]
    assert a_blk2.get_transactions.include?(tx)
    store_block a_blk2
    assert a_blk2.get_transactions.include?(tx)

    # receive in other db
    b_blk = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: b_db
    store_block b_blk
    assert_equal 0, b_blk.number
    assert_equal a_blk, b_blk

    b_blk2 = RLP.decode RLP.encode(a_blk2), sedes: Block, env: Env.new(b_blk.db)
    assert_equal a_blk2.full_hash, b_blk2.full_hash
    assert b_blk2.get_transactions.include?(tx)
    store_block b_blk2
    assert_equal a_blk2.full_hash, b_blk2.full_hash
    assert b_blk2.get_transactions.include?(tx)
  end

  def test_transaction
    blk = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: @db
    store_block blk

    blk = mine_next_block blk
    tx = get_transaction
    assert !blk.get_transactions.include?(tx)

    success, res = blk.apply_transaction tx
    assert blk.get_transactions.include?(tx)
    assert_equal 990.finney, blk.get_balance(@v)
    assert_equal 10.finney, blk.get_balance(@v2)
  end

  def test_transaction_serialization
    tx = get_transaction
    assert_equal RLP.decode(RLP.encode(tx), sedes: Transaction).full_hash, tx.full_hash
  end

  def test_invalid_transaction
    blk = mkgenesis initial_alloc: {@v2 => {balance: 1.ether}}, db: @db
    store_block blk

    tx = get_transaction
    blk = mine_next_block blk, transactions: [tx]

    assert_equal 0, blk.get_balance(@v)
    assert_equal 1.ether, blk.get_balance(@v2)
    assert !blk.get_transactions.include?(tx)
  end

  def test_prevhash
    g = mkgenesis db: @db
    chain = Chain.new Env.new(g.db), genesis: g
    l1 = mine_on_chain chain
    assert_equal g, l1.get_ancestor_list(2).first
  end

  def test_genesis_chain
    blk = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: @db
    chain = Chain.new Env.new(blk.db), genesis: blk

    assert chain.has_block(blk.full_hash)
    assert chain.include?(blk.full_hash)

    assert_equal blk, chain.get(blk.full_hash)
    assert_equal blk, chain.head
    assert_equal [], chain.get_children(blk)
    assert_equal [], chain.get_uncles(blk)
    assert_equal [blk], chain.get_chain
    assert_equal [blk], chain.get_chain(start: blk.full_hash)
    assert_equal [], chain.get_descendants(blk, count: 10)

    assert chain.index.has_block_by_number(0)
    assert !chain.index.has_block_by_number(1)
    assert_equal blk.full_hash, chain.index.get_block_by_number(0)
    assert_raises(KeyError) { chain.index.get_block_by_number(1) }
  end

  def test_simple_chain
    blk = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: @db
    store_block blk

    chain = Chain.new Env.new(blk.db), genesis: blk

    tx = get_transaction
    blk2 = mine_next_block blk, transactions: [tx]
    store_block blk2
    chain.add_block blk2

    assert chain.include?(blk.full_hash)
    assert chain.include?(blk2.full_hash)
    assert chain.has_block(blk2.full_hash)

    assert_equal blk2, chain.get(blk2.full_hash)
    assert_equal blk2, chain.head
    assert_equal [blk2], chain.get_children(blk)
    assert_equal [], chain.get_uncles(blk2)

    assert_equal [blk2, blk], chain.get_chain
    assert_equal [], chain.get_chain(count: 0)
    assert_equal [blk2], chain.get_chain(count: 1)
    assert_equal [blk2, blk], chain.get_chain(count: 2)
    assert_equal [blk2, blk], chain.get_chain(count: 100)
    assert_equal [blk], chain.get_chain(start: blk.full_hash)
    assert_equal [], chain.get_chain(start: blk.full_hash, count: 0)
    assert_equal [blk2, blk], chain.get_chain(start: blk2.full_hash)
    assert_equal [blk2], chain.get_chain(start: blk2.full_hash, count: 1)
    assert_equal [blk2], chain.get_descendants(blk, count: 10)
    assert_equal [blk2], chain.get_descendants(blk, count: 1)
    assert_equal [], chain.get_descendants(blk, count: 0)

    assert chain.index.has_block_by_number(1)
    assert !chain.index.has_block_by_number(2)
    assert_equal blk2.full_hash, chain.index.get_block_by_number(1)
    assert_raises(KeyError) { chain.index.get_block_by_number(2) }
    assert_equal [tx, blk2, 0], chain.index.get_transaction(tx.full_hash)
  end

  def test_add_side_chain
    # Remote: R0, R1
    r0 = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: @db
    store_block r0

    tx0 = get_transaction nonce: 0
    r1 = mine_next_block r0, transactions: [tx0]
    store_block r1
    assert r1.get_transactions.include?(tx0)

    # Local: L0, L1, L2
    alt_db = DB::EphemDB.new
    l0 = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: alt_db

    chain = Chain.new Env.new(l0.db), genesis: l0
    tx0 = get_transaction nonce: 0
    l1 = mine_next_block l0, transactions: [tx0]
    chain.add_block l1
    tx1 = get_transaction nonce: 1
    l2 = mine_next_block l1, transactions: [tx1]
    chain.add_block l2

    # receive serialized remote blocks, newest first
    rlp_blocks = [RLP.encode(r0), RLP.encode(r1)]
    rlp_blocks.each do |rlp_block|
      block = Block.deserialize RLP.decode(rlp_block), env: chain.env
      chain.add_block block
    end

    assert chain.include?(l2.full_hash)
  end

  def test_add_longer_side_chain
    # Remote: 4 blocks
    blk = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: @db
    store_block blk

    remote_blocks = [blk]
    3.times do |i|
      tx = get_transaction nonce: i
      blk = mine_next_block remote_blocks.last, transactions: [tx]
      store_block blk
      remote_blocks.push blk
    end

    # Local: L0, L1, L2
    alt_db = DB::EphemDB.new
    l0 = mkgenesis initial_alloc: {@v => {balance: 1.ether}}, db: alt_db

    chain = Chain.new Env.new(l0.db), genesis: l0
    tx0 = get_transaction nonce: 0
    l1 = mine_next_block l0, transactions: [tx0]
    chain.add_block l1
    tx1 = get_transaction nonce: 1
    l2 = mine_next_block l1, transactions: [tx1]
    chain.add_block l2

    # receive serialized remote blocks, newest first
    rlp_blocks = remote_blocks.map {|b| RLP.encode(b) }
    rlp_blocks.each do |rlp_block|
      block = Block.deserialize RLP.decode(rlp_block), env: chain.env
      chain.add_block block
    end

    assert_equal remote_blocks.last, chain.head
  end

  def test_reward_uncles
    local_coinbase = Utils.decode_hex '1'*40
    uncle_coinbase = Utils.decode_hex '2'*40

    blk0 = mkgenesis db: @db
    chain = Chain.new Env.new(blk0.db), genesis: blk0
    uncle = mine_on_chain chain, parent: blk0, coinbase: uncle_coinbase
    assert_equal chain.env.config[:block_reward], uncle.get_balance(uncle_coinbase)

    blk1 = mine_on_chain chain, parent: blk0, coinbase: local_coinbase
    assert chain.include?(blk1.full_hash)
    assert chain.include?(uncle.full_hash)
    assert uncle.full_hash != blk1.full_hash
    assert_equal blk1, chain.head
    assert_equal 1*chain.env.config[:block_reward], chain.head.get_balance(local_coinbase)
    assert_equal 0*chain.env.config[:block_reward], chain.head.get_balance(uncle_coinbase)

    blk2 = mine_on_chain chain, coinbase: local_coinbase
    assert_equal uncle.prevhash, blk2.get_parent.prevhash
    assert 1, blk2.uncles.size
    assert_equal blk2, chain.head
    assert_equal 2*chain.env.config[:block_reward]+chain.env.config[:nephew_reward], chain.head.get_balance(local_coinbase)
    assert_equal chain.env.config[:block_reward] * 7/8, chain.head.get_balance(uncle_coinbase)
  end

  # TODO ##########################################
  #
  # test for remote block with invalid transaction
  # test for multiple transactions from same address received
  #    in arbitrary order mined in the same block

  private

  def store_block(blk)
    blk.db.put blk.full_hash, RLP.encode(blk)
    assert_equal blk, Block.find(Env.new(blk.db), blk.full_hash)
  end

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
  def mine_on_chain(chain, parent: nil, transactions: [], coinbase: nil)
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

  def mine_next_block(parent, coinbase: nil, transactions: [])
    if coinbase.true?
      c = Chain.new parent.env, genesis: parent, coinbase: coinbase
    else
      c = Chain.new parent.env, genesis: parent
    end

    transactions.each {|tx| c.add_transaction tx }

    mine_on_chain c
  end

  def get_transaction(gasprice: 0, nonce: 0)
    Transaction.new(
      nonce: nonce,
      gasprice: gasprice,
      startgas: 100000,
      to: @v2,
      value: 10.finney,
      data: ''
    ).sign(@k)
  end

end
