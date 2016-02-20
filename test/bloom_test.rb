require 'test_helper'

class BloomTest < Minitest::Test
  include Ethereum

  def test_bloom_insert_and_query
    b = Bloom.from("\x01")
    assert_equal true, Bloom.query(b, "\x01")
    assert_equal false, Bloom.query(b, "\x00")
  end

  def test_bloom_bits
    assert_equal [[1323], [431], [1319]], Bloom.bits(Utils.decode_hex('0f572e5295c57f15886f9b263e2f6d2d6c7b5ec6'))
  end

end
