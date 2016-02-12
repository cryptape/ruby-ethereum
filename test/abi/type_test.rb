require 'test_helper'

class ABITypeTest < Minitest::Test
  include Ethereum::ABI

  def test_type_parse
    assert_equal Type.new('uint',  '8', []),              Type.parse("uint8")
    assert_equal Type.new('bytes', '32', []),             Type.parse("bytes32")
    assert_equal Type.new('uint',  '256',     [10]),      Type.parse("uint256[10]")
    assert_equal Type.new('fixed', '128x128', [1,2,3,0]), Type.parse("fixed128x128[1][2][3][]")
  end

  def test_type_parse_validations
    assert_raises(Type::ParseError) { Type.parse("string8") }
    assert_raises(Type::ParseError) { Type.parse("bytes33") }
    assert_raises(Type::ParseError) { Type.parse('hash')}
    assert_raises(Type::ParseError) { Type.parse('address8') }
    assert_raises(Type::ParseError) { Type.parse('bool8') }
    assert_raises(Type::ParseError) { Type.parse('decimal') }

    assert_raises(Type::ParseError) { Type.parse("int") }
    assert_raises(Type::ParseError) { Type.parse("int2") }
    assert_raises(Type::ParseError) { Type.parse("int20") }
    assert_raises(Type::ParseError) { Type.parse("int512") }

    assert_raises(Type::ParseError) { Type.parse("fixed") }
    assert_raises(Type::ParseError) { Type.parse("fixed256") }
    assert_raises(Type::ParseError) { Type.parse("fixed2x2") }
    assert_raises(Type::ParseError) { Type.parse("fixed20x20") }
    assert_raises(Type::ParseError) { Type.parse("fixed256x256") }
  end

end
