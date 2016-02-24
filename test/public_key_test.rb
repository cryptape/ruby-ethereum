# -*- encoding : ascii-8bit -*-

require 'test_helper'

class PublicKeyTest < Minitest::Test
  include Ethereum

  RAW = [40052878126280527701260741223305245603564636128202744842713277751919610658249,
         112427920116541844817408230468149218341228927370925731589596315545721129686052]

  ENCODES = {
    decimal: RAW,
    bin: "\x04X\x8d *\xfc\xc1\xeeJ\xb5%LxG\xec%\xb9\xa15\xbb\xda\x0f+\xc6\x9e\xe1\xa7\x14t\x9f\xd7}\xc9\xf8\x8f\xf2\xa0\r~u-D\xcb\xe1n\x1e\xbc\xf0\x89\x0bv\xec|x\x88a\t\xde\xe7l\xcf\xc8DT$",
    bin_compressed: "\x02X\x8d *\xfc\xc1\xeeJ\xb5%LxG\xec%\xb9\xa15\xbb\xda\x0f+\xc6\x9e\xe1\xa7\x14t\x9f\xd7}\xc9",
    hex: '04588d202afcc1ee4ab5254c7847ec25b9a135bbda0f2bc69ee1a714749fd77dc9f88ff2a00d7e752d44cbe16e1ebcf0890b76ec7c78886109dee76ccfc8445424',
    hex_compressed: '02588d202afcc1ee4ab5254c7847ec25b9a135bbda0f2bc69ee1a714749fd77dc9',
    bin_electrum: "X\x8d *\xfc\xc1\xeeJ\xb5%LxG\xec%\xb9\xa15\xbb\xda\x0f+\xc6\x9e\xe1\xa7\x14t\x9f\xd7}\xc9\xf8\x8f\xf2\xa0\r~u-D\xcb\xe1n\x1e\xbc\xf0\x89\x0bv\xec|x\x88a\t\xde\xe7l\xcf\xc8DT$",
    hex_electrum: '588d202afcc1ee4ab5254c7847ec25b9a135bbda0f2bc69ee1a714749fd77dc9f88ff2a00d7e752d44cbe16e1ebcf0890b76ec7c78886109dee76ccfc8445424'
  }

  def test_encode
    pubkey = PublicKey.new RAW
    ENCODES.each do |fmt, result|
      assert_equal result, pubkey.encode(fmt)
    end
  end

  def test_decode
    %i(decimal bin bin_compressed hex hex_compressed bin_electrum hex_electrum).each do |fmt|
      assert_equal RAW, PublicKey.new(ENCODES[fmt]).decode
    end
  end

  def test_format
    assert_equal :decimal, PublicKey.new([0,0]).format
    assert_equal :bin, PublicKey.new("\x04" + "\x00"*64).format
  end

  def test_to_bitcoin_address
    assert_equal '1CC3X2gu58d6wXUWMffpuzN9JAfTUWu4Kj', PublicKey.new(RAW).to_bitcoin_address
  end

  def test_to_address
    pubkey = PublicKey.new PrivateKey.new("\x01"*32).to_pubkey
    assert_equal "\x1ad/\x0e<:\xf5E\xe7\xac\xbd8\xb0rQ\xb3\x99\t\x14\xf1", pubkey.to_address
  end

end
