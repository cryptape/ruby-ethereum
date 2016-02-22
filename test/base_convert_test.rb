# -*- encoding : ascii-8bit -*-

require 'test_helper'

class BaseConvertTest < Minitest::Test
  include Ethereum

  def test_encode
    assert_equal '10', BaseConvert.encode(16, 16, 0)
    assert_equal '00000064', BaseConvert.encode(100, 16, 8)

    assert_equal '2j', BaseConvert.encode(100, 58, 0)
    assert_equal '1111112j', BaseConvert.encode(100, 58, 8)
  end

  def test_decode
    assert_equal 16, BaseConvert.decode('10', 16)
    assert_equal 100, BaseConvert.decode('00000064', 16)

    assert_equal 100, BaseConvert.decode('2j', 58)
    assert_equal 100, BaseConvert.decode('1111112j', 58)
  end

  def test_convert
    assert_equal '2j', BaseConvert.convert('001100100', 2, 58)
    assert_equal '1111112j', BaseConvert.convert('001100100', 2, 58, 8)
  end

end
