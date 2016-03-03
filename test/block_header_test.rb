# -*- encoding : ascii-8bit -*-

require 'test_helper'

class BlockHeaderTest < Minitest::Test
  include Ethereum

  def test_initialize
    h = BlockHeader.new(bloom: 100, nonce: "ffffffff")
    assert_equal Utils.keccak256_rlp([]), h.uncles_hash
    assert_equal 100, h.bloom
    assert_equal Env::DEFAULT_CONFIG[:genesis_difficulty], h.difficulty
    assert_equal Env::DEFAULT_CONFIG[:genesis_gas_limit], h.gas_limit
    assert_equal "ffffffff", h.nonce
  end

  def test_mining_hash
    h = BlockHeader.new(bloom: 100, nonce: "ffffffff")
    assert_equal '43b0b13ebe81db9d418af6366e8b677055d05dd9ee7005abea29dfb6f2f017ca', Utils.encode_hex(h.mining_hash)
  end

end
