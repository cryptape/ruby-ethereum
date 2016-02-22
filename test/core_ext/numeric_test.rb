# -*- encoding : ascii-8bit -*-

require 'test_helper'

class NumericTest < Minitest::Test

  def test_denominations
    assert_equal 10**18, 1.ether
    assert_equal 10**15, 1.finney
    assert_equal 10**12, 1.szabo
    assert_equal 1, 1.wei
  end

end
