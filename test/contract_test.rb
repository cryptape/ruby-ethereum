# -*- encoding : ascii-8bit -*-

require 'test_helper'

class ContractTest < Minitest::Test
  include Ethereum

  def test_make_address
    assert_equal "\xbdw\x04\x16\xa34_\x91\xe4\xb3Ev\xcb\x80JWo\xa4\x8e\xb1", Contract.make_address("\x00"*20, 0)
  end

end
