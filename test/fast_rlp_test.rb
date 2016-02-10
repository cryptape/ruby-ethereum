require 'test_helper'

class FastRLPTest < Minitest::Test
  include Ethereum::FastRLP

  def test_encode_nested_bytes
    assert_equal RLP.encode("".b), encode_nested_bytes("".b)

    nested_bytes = ["a".b, "hello!".b, ["foo".b], ["bar".b, ["ear".b]]]
    assert_equal RLP.encode(nested_bytes), encode_nested_bytes(nested_bytes)
  end

end
