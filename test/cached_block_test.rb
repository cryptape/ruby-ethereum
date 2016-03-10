# -*- encoding : ascii-8bit -*-

require 'test_helper'

class CachedBlockTest < Minitest::Test
  include Ethereum

  def setup
    @db = DB::EphemDB.new
    @db.put Trie::BLANK_ROOT, RLP.encode(Trie::BLANK_NODE)

    @env = Env.new @db

    @header = BlockHeader.new(bloom: 100, nonce: 'ffffffff')
    @header_rlp = RLP.encode @header
  end

  def test_create_cached
    blk = Block.build_from_header @header_rlp, @env
    cached = CachedBlock.create_cached blk

    assert_equal 100, cached.bloom
    assert_equal 'ffffffff', cached.nonce

    assert_equal blk.hash, cached.hash
    assert_equal blk.full_hash, cached.full_hash

    assert_raises(NotImplementedError) { cached.state_root = '' }
    assert_raises(NotImplementedError) { cached.revert }
  end
end
