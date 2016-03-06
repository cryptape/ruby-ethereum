# -*- encoding : ascii-8bit -*-

require 'test_helper'

class CoreExtArrayTest < Minitest::Test

  def test_safe_slice
    assert_equal nil, [].safe_slice(1024)
    assert_equal [], [].safe_slice(1024,0)
    assert_equal [], [].safe_slice(1024,1024)
    assert_equal [], [].safe_slice(1024..2048)
  end

  def test_zero_length_slice_optimization
    assert_equal [], [].safe_slice(2**128, 0)
  end

end
