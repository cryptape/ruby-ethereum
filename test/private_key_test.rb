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

  def test_to_pubkey
    assert_equal "\x04\x1b\x84\xc5V{\x12d@\x99]>\xd5\xaa\xba\x05e\xd7\x1e\x184`H\x19\xff\x9c\x17\xf5\xe9\xd5\xdd\x07\x8fp\xbe\xaf\x8fX\x8bT\x15\x07\xfe\xd6\xa6B\xc5\xabB\xdf\xdf\x81 \xa7\xf69\xdeQ\"\xd4zi\xa8\xe8\xd1", PrivateKey.new("\x01"*32).to_pubkey
    assert_equal '041b84c5567b126440995d3ed5aaba0565d71e1834604819ff9c17f5e9d5dd078f70beaf8f588b541507fed6a642c5ab42dfdf8120a7f639de5122d47a69a8e8d1', PrivateKey.new("01"*32).to_pubkey
    assert_equal "\x03\x1b\x84\xc5V{\x12d@\x99]>\xd5\xaa\xba\x05e\xd7\x1e\x184`H\x19\xff\x9c\x17\xf5\xe9\xd5\xdd\x07\x8f", PrivateKey.new(PrivateKey.new("\x01"*32).encode(:bin_compressed)).to_pubkey
    assert_equal '031b84c5567b126440995d3ed5aaba0565d71e1834604819ff9c17f5e9d5dd078f', PrivateKey.new(PrivateKey.new("\x01"*32).encode(:hex_compressed)).to_pubkey
  end

  def test_to_address
    assert_equal '1BCwRkTsYzK5aNK4sdF7Bpti3PhrkPtLc4', PrivateKey.new("\x01"*32).to_address
  end

end
