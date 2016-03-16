# -*- encoding : ascii-8bit -*-

require 'test_helper'

class EthashRubyHashimotoTest < Minitest::Test
  include Ethereum

  def setup
    @h = EthashRuby::Hashimoto.new
  end

  def test_fnv
    assert_equal 0, @h.fnv(0, 0)
    assert_equal 16777619, @h.fnv(1, 0)
    assert_equal 1, @h.fnv(0, 1)
    assert_equal 16777619, @h.fnv(1, 2**32)
    assert_equal 1, @h.fnv(2**32, 1)
    assert_equal 1677761800, @h.fnv(100, 100)
    assert_equal 2835726498, @h.fnv(937, 937)
  end

  def test_get_full_size
    assert_equal 1073739904, @h.get_full_size(0)
    assert_equal 1392507008, @h.get_full_size(1150000)
  end

end
