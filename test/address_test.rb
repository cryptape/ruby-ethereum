# -*- encoding : ascii-8bit -*-

require 'test_helper'

class AddressTest < Minitest::Test
  include Ethereum

  def test_base58_check_to_bytes
    assert_equal 'ethereum', Address.base58_check_to_bytes('12v3WKYzeJnRZWgfV3')
    assert_equal 'ethereum', Address.base58_check_to_bytes('x4BdNKWArBWmHMTgc')
  end

  def test_bytes_to_base58_check
    assert_equal '12v3WKYzeJnRZWgfV3', Address.bytes_to_base58_check("ethereum")
    assert_equal 'x4BdNKWArBWmHMTgc', Address.bytes_to_base58_check("ethereum", 11)
  end

end
