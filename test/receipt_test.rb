# -*- encoding : ascii-8bit -*-

require 'test_helper'

class ReceiptTest < Minitest::Test
  include Ethereum

  def test_bloom_override
    r = Receipt.new '', 100, []
    assert_equal 0, r.bloom
  end

end
