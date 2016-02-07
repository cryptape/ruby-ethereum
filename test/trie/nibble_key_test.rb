require 'test_helper'

class Ethereum::Trie
  class NibbleKeyTest < Minitest::Test
    def test_from_str
      assert_equal NibbleKey, NibbleKey.from_str('').class

      assert_equal [], NibbleKey.from_str('')
      assert_equal [6, 8], NibbleKey.from_str('h')
      assert_equal [6, 8, 6, 5, 6, 12, 6, 12, 6, 15], NibbleKey.from_str('hello')
    end

    def test_prefix_check
      assert_equal true, NibbleKey.new([1,2]).prefix?([1,2,3,4])
      assert_equal true, NibbleKey.new([1,2]).prefix?(NibbleKey.new([1,2,3,4]))

      assert_equal false, NibbleKey.new([1,2]).prefix?([1])
      assert_equal false, NibbleKey.new([1,2]).prefix?(NibbleKey.new([1]))

      assert_equal false, NibbleKey.new([1,2]).prefix?([1,3,4,5])
      assert_equal false, NibbleKey.new([1,2]).prefix?(NibbleKey.new([1,3,4,5]))
    end

    def test_slice_is_also_nibble_key
      assert_equal NibbleKey, NibbleKey.new([1,2,3])[1..-1].class
    end

  end
end
