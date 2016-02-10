require 'test_helper'

class Ethereum::Trie
  class NibbleKeyTest < Minitest::Test
    def test_from_string
      assert_equal NibbleKey, NibbleKey.from_string('').class

      assert_equal [], NibbleKey.from_string('')
      assert_equal [6, 8], NibbleKey.from_string('h')
      assert_equal [6, 8, 6, 5, 6, 12, 6, 12, 6, 15], NibbleKey.from_string('hello')
    end

    def test_to_string
      assert_equal '', NibbleKey.to_string([])
      assert_equal 'h', NibbleKey.to_string([6, 8])
      assert_equal 'hello', NibbleKey.to_string([6, 8, 6, 5, 6, 12, 6, 12, 6, 15])

      assert_equal 'hello', NibbleKey.new([6, 8, 6, 5, 6, 12, 6, 12, 6, 15]).to_string
    end

    def test_prefix_check
      assert_equal true, NibbleKey.new([1,2]).prefix?([1,2,3,4])
      assert_equal true, NibbleKey.new([1,2]).prefix?(NibbleKey.new([1,2,3,4]))

      assert_equal false, NibbleKey.new([1,2]).prefix?([1])
      assert_equal false, NibbleKey.new([1,2]).prefix?(NibbleKey.new([1]))

      assert_equal false, NibbleKey.new([1,2]).prefix?([1,3,4,5])
      assert_equal false, NibbleKey.new([1,2]).prefix?(NibbleKey.new([1,3,4,5]))
    end

    def test_common_prefix
      assert_equal [], NibbleKey.new([1,2,3]).common_prefix([2,3,4])
      assert_equal [1,2,3], NibbleKey.new([1,2,3,4,5]).common_prefix([1,2,3,5,6,7])
    end

    def test_slice_is_also_nibble_key
      assert_equal NibbleKey, NibbleKey.new([1,2,3])[1..-1].class
    end

    def test_encode
      assert_equal "\x00", NibbleKey.encode([])
      assert_equal "\x11h", NibbleKey.encode([1,6,8])

      assert_equal "\x00", NibbleKey.new([]).encode
      assert_equal "\x00h", NibbleKey.from_string('h').encode

      assert_equal "\x11h", NibbleKey.new([1,6,8]).encode
      assert_equal " h", NibbleKey.new([6,8,NibbleKey::NIBBLE_TERMINATOR]).encode
      assert_equal "0h", NibbleKey.new([0,6,8,NibbleKey::NIBBLE_TERMINATOR]).encode
    end

    def test_terminate_check
      assert_equal true, NibbleKey.decode(" \x01\x04\x11\r\x81l8\x08\x12\xa4'\x96\x8e\xce\x99\xb1\xc9c\xdf\xbc\xe6").terminate?
    end

  end
end
