# -*- encoding : ascii-8bit -*-

require 'test_helper'

class VMCallDataTest < Minitest::Test
  include Ethereum

  def setup
    @calldata = VM::CallData.new [1,2,3,4,5], 1, 3
  end

  def test_call_data_extract_all
    assert_equal "\x02\x03\x04", @calldata.extract_all
  end

  def test_call_data_extract32
    assert_equal Utils.big_endian_to_int("\x04"+"\x00"*31), @calldata.extract32(2)
  end

  def test_extract_copy
    mem = []
    @calldata.extract_copy mem, 1, 1, 2
    assert_equal [nil, 3,4], mem
  end

end
