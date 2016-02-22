# -*- encoding : ascii-8bit -*-

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

  def test_type_size
    assert_nil Type.parse("string").size
    assert_nil Type.parse("bytes").size
    assert_nil Type.parse("uint256[]").size
    assert_nil Type.parse("uint256[4][]").size

    assert_equal 32, Type.parse("uint256").size
    assert_equal 32, Type.parse("fixed128x128").size
    assert_equal 32, Type.parse("bool").size

    assert_equal 64, Type.parse("uint256[2]").size
    assert_equal 128, Type.parse("address[2][2]").size
    assert_equal 1024, Type.parse("ufixed192x64[2][2][2][2][2]").size
  end

  def test_subtype_of_array
    assert_equal [], Type.parse("uint256").subtype.dims
    assert_equal [2], Type.parse("uint256[2][]").subtype.dims
    assert_equal [2], Type.parse("uint256[2][2]").subtype.dims
  end

end
