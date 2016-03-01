# -*- encoding : ascii-8bit -*-

require 'test_helper'

class VMStateTest < Minitest::Test
  include Ethereum

  def test_customize_attributes
    s = VM::State.new(a: 1, b: 2)
    assert_equal 1, s.a
    assert_equal 2, s.b

    s.a = 3
    assert_equal 3, s.a
  end

  def initialize_with_attributes
    s = VM::State.new(gas: 100)
    assert_equal 100, s.gas
  end

end
