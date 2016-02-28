# -*- encoding : ascii-8bit -*-

require 'test_helper'

class BlockTest < Minitest::Test
  include Ethereum

  def setup
    @db = DB::EphemDB.new
    @db.put Trie::BLANK_ROOT, RLP.encode(Trie::BLANK_NODE)

    @env = Env.new @db

    @header = BlockHeader.new(bloom: 100, nonce: 'ffffffff')
    @header_rlp = RLP.encode @header
  end

  def test_build_from_header
    blk = Block.build_from_header @header_rlp, @env
    assert_equal 100, blk.bloom
    assert_equal 'ffffffff', blk.nonce
  end

  def test_build_from_parent
    Miner.stub(:check_pow, true) do
      parent = Block.build_from_header @header_rlp, @env
      coinbase = "\x02"*20
      blk = Block.build_from_parent parent, coinbase

      assert_equal parent.number+1, blk.number
      assert_equal coinbase, blk.coinbase
      assert_equal parent.full_hash, blk.prevhash
      assert_equal parent.state_root, blk.state_root
    end
  end

  def test_calc_difficulty
    parent = Block.build_from_header @header_rlp, @env
    assert_equal 131136, Block.calc_difficulty(parent, 1)
    assert_equal 131136, Block.calc_difficulty(parent, 10)
    assert_equal 131072, Block.calc_difficulty(parent, 15)
    assert_equal 131072, Block.calc_difficulty(parent, 9999)
  end

  def test_calc_gaslimit
    parent = Block.build_from_header @header_rlp, @env
    assert_equal 3141592, Block.calc_gaslimit(parent)
  end

  def test_initialize
    parent = Block.build_from_header @header_rlp, @env

    header = BlockHeader.new(
      prevhash: @header.full_hash,
      uncles_hash: "\x00"*32,
      coinbase: "\x01"*20,

      number: parent.number+1,
      timestamp: 15,
      difficulty: Block.calc_difficulty(parent, 15)
    )

    Miner.stub(:check_pow, true) do
      blk = Block.new header, env: @env, parent: parent
      assert_equal parent.number+1, blk.number
      assert_equal blk, header.block
    end
  end

end

class BlockFixtureTest < Minitest::Test
  include Ethereum

  run_fixtures "BlockchainTests", options: {limit: 500}

  EXCLUDES = %w(
    bcWalletTest_walletReorganizeOwners
    bl10251623GO_randomBlockTest
    bl201507071825GO_randomBlockTest
  )

  def on_fixture_test(name, pairs)
    return if EXCLUDES.include?(name)
  end

end
