require 'test_helper'

class UtilsTest < Minitest::Test
  include Ethereum::Utils

  def test_keccak_256
    assert_equal "\xc5\xd2F\x01\x86\xf7#<\x92~}\xb2\xdc\xc7\x03\xc0\xe5\x00\xb6S\xca\x82';{\xfa\xd8\x04]\x85\xa4p".b, keccak_256('')
  end

end
