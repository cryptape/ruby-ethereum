require 'test_helper'

class ABITest < Minitest::Test
  include Ethereum::ABI

  def test_parse_type
    assert_equal ['uint',  '8',       []],        parse_type("uint8")
    assert_equal ['bytes', '32',      []],        parse_type("bytes32")
    assert_equal ['uint',  '256',     [10]],      parse_type("uint256[10]")
    assert_equal ['fixed', '128x128', [1,2,3,0]], parse_type("fixed128x128[1][2][3][]")
  end

  def test_parse_type_validations
    assert_raises(TypeParseError) { parse_type("string8") }
    assert_raises(TypeParseError) { parse_type("bytes33") }
    assert_raises(TypeParseError) { parse_type('hash')}
    assert_raises(TypeParseError) { parse_type('address8') }
    assert_raises(TypeParseError) { parse_type('bool8') }
    assert_raises(TypeParseError) { parse_type('decimal') }

    assert_raises(TypeParseError) { parse_type("int") }
    assert_raises(TypeParseError) { parse_type("int2") }
    assert_raises(TypeParseError) { parse_type("int20") }
    assert_raises(TypeParseError) { parse_type("int512") }

    assert_raises(TypeParseError) { parse_type("fixed") }
    assert_raises(TypeParseError) { parse_type("fixed256") }
    assert_raises(TypeParseError) { parse_type("fixed2x2") }
    assert_raises(TypeParseError) { parse_type("fixed20x20") }
    assert_raises(TypeParseError) { parse_type("fixed256x256") }
  end

end
