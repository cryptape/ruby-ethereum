# -*- encoding : ascii-8bit -*-

require 'test_helper'

class ArrayTest < Minitest::Test

  def test_safe_slice
    assert_equal nil, [].safe_slice(1024)
    assert_equal [], [].safe_slice(1024,0)
    assert_equal [], [].safe_slice(1024,1024)
    assert_equal [], [].safe_slice(1024..2048)
  end

end
