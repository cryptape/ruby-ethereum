require 'test_helper'

class FastRLPTest < Minitest::Test
  include Ethereum::FastRLP

  def test_encode_nested_bytes_raise_exception_on_invalid_argument
    assert_raises(ArgumentError) { encode_nested_bytes("") }
    assert_raises(ArgumentError) { encode_nested_bytes([""]) }
  end

  def test_encode_nested_bytes
    assert_equal encode("".b), encode_nested_bytes("".b)

    nested_bytes = ["a".b, "hello!".b, ["foo".b], ["bar".b, ["ear".b]]]
    assert_equal encode(nested_bytes), encode_nested_bytes(nested_bytes)
  end

end
