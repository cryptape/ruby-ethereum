# -*- encoding : ascii-8bit -*-

require 'test_helper'

class Secp256k1Test < Minitest::Test

  def test_generate_key_pair
    priv, pub = Bitcoin::Secp256k1.generate_key_pair true
    assert_equal [32, 33], [priv, pub].map(&:bytesize)
  end

  def test_generate_key
    key = Bitcoin::Secp256k1.generate_key true
    assert_equal true, key.compressed

    key = Bitcoin::Secp256k1.generate_key false
    assert_equal false, key.compressed
  end

  def test_sign_and_verify
    priv, pub = Bitcoin::Secp256k1.generate_key_pair
    signature = Bitcoin::Secp256k1.sign("ethereum", priv)
    assert_equal true, Bitcoin::Secp256k1.verify("ethereum", signature, pub)
  end

  def test_sign_compact_and_recover
    # compressed
    priv, pub = Bitcoin::Secp256k1.generate_key_pair true
    signature = Bitcoin::Secp256k1.sign_compact("ethereum", priv, true)
    assert_equal 65, signature.bytesize

    pub2 = Bitcoin::Secp256k1.recover_compact("ethereum", signature)
    assert_equal 33, pub2.bytesize
    assert_equal pub, pub2

    # uncompressed
    priv, pub = Bitcoin::Secp256k1.generate_key_pair false
    signature = Bitcoin::Secp256k1.sign_compact("ethereum", priv, false)
    assert_equal 65, signature.bytesize

    pub2 = Bitcoin::Secp256k1.recover_compact("ethereum", signature)
    assert_equal 65, pub2.bytesize
    assert_equal pub, pub2
  end

  def test_deterministic_signature_using_rfc6979
    priv, pub = Bitcoin::Secp256k1.generate_key_pair
    first  = Bitcoin::Secp256k1.sign("ethereum", priv)
    second = Bitcoin::Secp256k1.sign("ethereum", priv)
    assert_equal second, first
  end

end
