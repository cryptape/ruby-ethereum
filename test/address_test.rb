# -*- encoding : ascii-8bit -*-

require 'test_helper'

class AddressTest < Minitest::Test
  include Ethereum

  def test_initialize_with_different_formats
    assert_equal true, Address.new('').blank?

    assert_equal "\x00"*20, Address.new("00"*20).to_bytes
    assert_equal "\x00"*20, Address.new(Address.new("00"*20).to_bytes(true)).to_bytes
    assert_equal "\x00"*20, Address.new("0x"+"00"*20).to_bytes
    assert_equal "\x00"*20, Address.new("0x"+Address.new("00"*20).to_hex(true)).to_bytes
    assert_equal "\x00"*20, Address.new("\x00"*20).to_bytes
    assert_equal "\x00"*20, Address.new(Address.new("\x00"*20).to_bytes(true)).to_bytes
  end

  def test_validate_checksum
    assert_raises(ChecksumError) { Address.new("\x00"*24) }
  end

end
