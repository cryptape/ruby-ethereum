# -*- encoding : ascii-8bit -*-

require 'test_helper'

class Secp256k1Test < Minitest::Test
  include Ethereum

  def test_generate_key_pair
    priv, pub = Secp256k1.generate_key_pair true
    assert_equal [32, 33], [priv, pub].map(&:bytesize)
  end

  def test_sign_and_verify
    priv, pub = Secp256k1.generate_key_pair
    signature = Secp256k1.sign("ethereum", priv)
    assert_equal true, Secp256k1.verify("ethereum", signature, pub)
  end

  def test_sign_compact_and_recover
    # compressed
    priv, pub = Secp256k1.generate_key_pair true
    signature = Secp256k1.sign_compact("ethereum", priv, true)
    p Ethereum::Utils.encode_hex(signature)
    assert_equal 65, signature.bytesize

    pub2 = Secp256k1.recover_compact("ethereum", signature)
    assert_equal 33, pub2.bytesize
    assert_equal pub, pub2
    p pub2

    # uncompressed
    priv, pub = Secp256k1.generate_key_pair false
    signature = Secp256k1.sign_compact("ethereum", priv, false)
    p Ethereum::Utils.encode_hex(signature)
    assert_equal 65, signature.bytesize

    pub2 = Secp256k1.recover_compact("ethereum", signature)
    assert_equal 65, pub2.bytesize
    assert_equal pub, pub2
    p pub2
  end

  def test_deterministic_signature_using_rfc6979
    priv, pub = Secp256k1.generate_key_pair
    first  = Secp256k1.sign("ethereum", priv)
    second = Secp256k1.sign("ethereum", priv)
    assert_equal second, first
  end

  def test_encode_decode_signature
    assert_equal "\x00"*65, Secp256k1.encode_sigature(27,0,0)
    assert_equal ("\x01" + "\x00"*31+"\x02"+"\x00"*31+"\x03"), Secp256k1.encode_sigature(28,2,3)

    assert_equal [27,0,0], Secp256k1.decode_signature(Secp256k1.encode_sigature(27,0,0))
    assert_equal [28,2,3], Secp256k1.decode_signature(Secp256k1.encode_sigature(28,2,3))
  end

  def test_ecdsa_recover_raw

  end

end
