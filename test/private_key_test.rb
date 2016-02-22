# -*- encoding : ascii-8bit -*-

require 'test_helper'

class PrivateKeyTest < Minitest::Test
  include Ethereum

  def test_encode
    assert_equal 0, PrivateKey.new(0).encode(:decimal)
    assert_equal ("\x00"*32+"\x01"), PrivateKey.new(0).encode(:bin_compressed)
    assert_equal ("00"*32+"01"), PrivateKey.new(0).encode(:hex_compressed)
    assert_equal 'ajCmMoA6v3tMAz296GzcWga3k4ojLQpk7j2iaZzax6qHCUUzVzJq', PrivateKey.new(0).encode(:wif_compressed, 100)
  end

  def test_decode
    assert_equal 0, PrivateKey.new(0).decode(:decimal)
    assert_equal 0, PrivateKey.new("\x00"*32+"\x01").decode(:bin_compressed)
    assert_equal 0, PrivateKey.new("00"*32+"01").decode(:hex_compressed)
    assert_equal 0, PrivateKey.new('ajCmMoA6v3tMAz296GzcWga3k4ojLQpk7j2iaZzax6qHCUUzVzJq').decode(:wif_compressed)
  end

  def test_format
    assert_equal :decimal, PrivateKey.new(1).format
    assert_equal :hex, PrivateKey.new('ff'*32).format
  end

end
