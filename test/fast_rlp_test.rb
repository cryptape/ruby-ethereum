# -*- encoding : ascii-8bit -*-

require 'test_helper'

class FastRLPTest < Minitest::Test
  include Ethereum::FastRLP

  def test_encode_nested_bytes
    assert_equal RLP.encode(""), encode_nested_bytes("")

    nested_bytes = ["a", "hello!", ["foo"], ["bar", ["ear"]]]
    assert_equal RLP.encode(nested_bytes), encode_nested_bytes(nested_bytes)
  end

end
