# -*- encoding : ascii-8bit -*-

require 'test_helper'

class EthashHashimotoTest < Minitest::Test
  include Ethereum

  def setup
    @h = Ethash::Hashimoto.new
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

  def test_keccak512
    assert_equal [2620437088, 2865270727, 2892105390, 2338067752, 1006496725, 702760908, 3861168948, 2100008890, 2644375569, 2659489748, 1971258991, 3262865397, 1844246636, 2612442309, 3265633223, 3404757258], @h.keccak512('ethereum')
  end

  def test_hash_words
    hw = @h.hash_words [1,2,3,4] do |v|
      Utils.keccak512 v
    end
    assert_equal 16, hw.size
    assert_equal [2554002749, 1041503378, 2974413858, 2730348567, 772461198, 3781937804, 186156836, 356303031, 2629235720, 3404506343, 2222070485, 4178555351, 97754719, 3959840754, 87471227, 378843215], hw
  end

  def test_serialize_hash
    assert_equal '', @h.serialize_hash([])
    assert_equal "\x01\x00\x00\x00\x02\x00\x00\x00\x03\x00\x00\x00\x04\x00\x00\x00", @h.serialize_hash([1,2,3,4])
  end

  def test_deserialize_hash
    assert_equal [], @h.deserialize_hash('')
    assert_equal [1,2,3,4], @h.deserialize_hash("\x01\x00\x00\x00\x02\x00\x00\x00\x03\x00\x00\x00\x04\x00\x00\x00")
  end

  def test_decode_int
    assert_equal 0, @h.decode_int('')
    assert_equal 16909060, @h.decode_int("\x04\x03\x02\x01")
  end

  def test_encode_int
    assert_equal '', @h.encode_int(0)
    assert_equal "\x04\x03\x02\x01", @h.encode_int(16909060)
  end

  def test_get_full_size
    assert_equal 1073739904, @h.get_full_size(0)
    assert_equal 1392507008, @h.get_full_size(1150000)
  end

end
