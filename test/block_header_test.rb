require 'test_helper'

class BlockHeaderTest < Minitest::Test
  include Ethereum

  def test_initialize
    h = BlockHeader.new(bloom: 100, nonce: "ffffffff")
    assert_equal Utils.keccak_rlp([]), h.uncles_hash
    assert_equal 100, h.bloom
    assert_equal Env::DEFAULT_CONFIG[:genesis_difficulty], h.difficulty
    assert_equal Env::DEFAULT_CONFIG[:genesis_gas_limit], h.gas_limit
    assert_equal "ffffffff", h.nonce
  end

end
