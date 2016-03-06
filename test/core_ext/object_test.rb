# -*- encoding : ascii-8bit -*-

require 'test_helper'

class CoreExtObjectTest < Minitest::Test

  def test_false_predict
    assert_equal true, [].false?
    assert_equal false, [0].false?
    assert_equal true, ''.false?
    assert_equal false, ' '.false?
    assert_equal true, nil.false?
    assert_equal false, true.false?
    assert_equal true, false.false?
    assert_equal false, 1.false?
    assert_equal true, 0.false?
    assert_equal true, 0.0.false?
  end

end
