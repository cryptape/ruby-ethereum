require 'test_helper'

class ABITest < Minitest::Test
  include Ethereum::ABI

  def test_abi_decode_primitive_type_real
    type = Type.parse 'real128x128'

    real_data = encode_primitive_type type, 1
    assert_equal 1, decode_primitive_type(type, real_data)

    real_data = encode_primitive_type type, 2**127-1
    assert_equal (2**127-1).to_f, decode_primitive_type(type, real_data)

    real_data = encode_primitive_type type, -1
    assert_equal -1, decode_primitive_type(type, real_data)

    real_data = encode_primitive_type type, -2**127
    assert_equal -2**127, decode_primitive_type(type, real_data)
  end
end
