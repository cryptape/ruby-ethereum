# -*- encoding : ascii-8bit -*-

require 'test_helper'

class UtilsTest < Minitest::Test
  include Ethereum::Utils

  def test_keccak256
    assert_equal "\xc5\xd2F\x01\x86\xf7#<\x92~}\xb2\xdc\xc7\x03\xc0\xe5\x00\xb6S\xca\x82';{\xfa\xd8\x04]\x85\xa4p", keccak256('')
  end

  def test_keccak256_rlp
    assert_equal "V\xe8\x1f\x17\x1b\xccU\xa6\xff\x83E\xe6\x92\xc0\xf8n[H\xe0\x1b\x99l\xad\xc0\x01b/\xb5\xe3c\xb4!", keccak256_rlp('')
    assert_equal "_\xe7\xf9w\xe7\x1d\xba.\xa1\xa6\x8e!\x05{\xee\xbb\x9b\xe2\xac0\xc6A\n\xa3\x8dO?\xbeA\xdc\xff\xd2", keccak256_rlp(1)
    assert_equal "\x1d\xccM\xe8\xde\xc7]z\xab\x85\xb5g\xb6\xcc\xd4\x1a\xd3\x12E\x1b\x94\x8at\x13\xf0\xa1B\xfd@\xd4\x93G", keccak256_rlp([])
    assert_equal "YZ\xef\x85BA8\x89\x08?\x83\x13\x88\xcfv\x10\x0f\xd8a:\x97\xaf\xb8T\xdb#z#PF89", keccak256_rlp([1, [2,3], "4", ["5", [6]]])
  end

  def test_double_sha256
    assert_equal "]\xf6\xe0\xe2v\x13Y\xd3\n\x82u\x05\x8e)\x9f\xcc\x03\x81SEE\xf5\\\xf4>A\x98?]L\x94V", double_sha256('')
  end

  def test_ripemd160
    assert_equal "\xc8\x1b\x94\x934 \"\x1az\xc0\x04\xa9\x02B\xd8\xb1\xd3\xe5\x07\r", ripemd160("\x00")
  end

  def test_hash160
    assert_equal "\x9f\x7f\xd0\x96\xd3~\xd2\xc0\xe3\xf7\xf0\xcf\xc9$\xbe\xefO\xfc\xebh", hash160("\x00")
    assert_equal "9f7fd096d37ed2c0e3f7f0cfc924beef4ffceb68", hash160_hex("\x00")
  end

  def test_mod_exp
    assert_equal 1, mod_exp(2, 10, 1023)
  end

  def test_mod_mul
    assert_equal 1, mod_mul(2, 4, 7)
  end

  def test_base58_check_to_bytes
    assert_equal 'ethereum', base58_check_to_bytes('12v3WKYzeJnRZWgfV3')
    assert_equal 'ethereum', base58_check_to_bytes('x4BdNKWArBWmHMTgc')
  end

  def test_bytes_to_base58_check
    assert_equal '12v3WKYzeJnRZWgfV3', bytes_to_base58_check("ethereum")
    assert_equal 'x4BdNKWArBWmHMTgc', bytes_to_base58_check("ethereum", 11)
  end

  def test_ceil32
    assert_equal 0,   ceil32(0)
    assert_equal 32,  ceil32(1)
    assert_equal 256, ceil32(256)
    assert_equal 256, ceil32(250)
  end

  def test_big_endian_to_int
    assert_equal 255, big_endian_to_int("\xff")
    assert_equal 255, big_endian_to_int("\x00\x00\xff")
  end

  def test_normalize_address
    assert_equal Ethereum::Address::BLANK, normalize_address(Ethereum::Address::BLANK, allow_blank: true)
    assert_raises(Ethereum::ValueError) { normalize_address(Ethereum::Address::BLANK) }
  end

end
