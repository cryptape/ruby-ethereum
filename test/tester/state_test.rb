# -*- encoding : ascii-8bit -*-

require 'test_helper'

class TesterStateTest < Minitest::Test
  include Ethereum

  def setup
    @s = Tester::State.new
  end

  def test_blockhashes_10
    @s.mine 10
    o = (1..10).map {|i| @s.block.get_ancestor_hash(i) }

    assert_equal @s.block.get_parent.full_hash, o[0]
    assert_equal @s.blocks[9].full_hash, o[0]

    (1..8).each do |i|
      assert_equal @s.blocks[9-i].full_hash, o[i]
    end
  end

  def test_blockhashes_300
    @s.mine 300
    o = (1..256).map {|i| @s.block.get_ancestor_hash(i) }

    assert_equal @s.block.get_parent.full_hash, o[0]
    assert_equal @s.blocks[299].full_hash, o[0]

    (1..255).each do |i|
      assert_equal @s.blocks[299-i].full_hash, o[i]
    end

  end
end
