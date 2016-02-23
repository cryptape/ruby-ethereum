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
    assert_equal 65, signature.bytesize

    pub2 = Secp256k1.recover_compact("ethereum", signature)
    assert_equal 33, pub2.bytesize
    assert_equal pub, pub2

    # uncompressed
    priv, pub = Secp256k1.generate_key_pair false
    signature = Secp256k1.sign_compact("ethereum", priv, false)
    assert_equal 65, signature.bytesize

    pub2 = Secp256k1.recover_compact("ethereum", signature)
    assert_equal 65, pub2.bytesize
    assert_equal pub, pub2
  end

  def test_deterministic_signature_using_rfc6979
    priv, pub = Secp256k1.generate_key_pair
    first  = Secp256k1.sign("ethereum", priv)
    second = Secp256k1.sign("ethereum", priv)
    assert_equal second, first
  end

  def test_encode_decode_signature
    assert_equal "GwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", Secp256k1.encode_signature(27,0,0)
    assert_equal "HAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM=", Secp256k1.encode_signature(28,2,3)

    assert_equal [27,0,0], Secp256k1.decode_signature(Secp256k1.encode_signature(27,0,0))
    assert_equal [28,2,3], Secp256k1.decode_signature(Secp256k1.encode_signature(28,2,3))
  end

  def test_ecdsa_raw_sign
    assert_equal [27, 38165775396159397919574584548038030579745720245771730671534243853171015175317, 54089208988112399457865773336714133188737260542214125621062935094623801683095], Secp256k1.ecdsa_raw_sign("ethereum", "\x01"*32)
    assert_equal [28, 59580848073865221727567986518100350182047399960389055162689843514473302438413, 25921690152351439173205788059889699198429497668583599251700245280747968617007], Secp256k1.ecdsa_raw_sign("ethereum", "\x02"*32)
  end

  def test_ecdsa_raw_verify
    priv, pub = Secp256k1.generate_key_pair
    v, r, s = Secp256k1.ecdsa_raw_sign('ethereum', priv)
    assert_equal true, Secp256k1.ecdsa_raw_verify('ethereum', [v,r,s], pub)
  end

  def test_ecdsa_raw_recover
    # compressed
    priv, pub = Secp256k1.generate_key_pair true
    v, r, s = Secp256k1.ecdsa_raw_sign('ethereum', priv, true)
    assert_equal pub, Secp256k1.ecdsa_raw_recover('ethereum', [v,r,s])

    # uncompressed
    priv, pub = Secp256k1.generate_key_pair false
    v, r, s = Secp256k1.ecdsa_raw_sign('ethereum', priv)
    assert_equal pub, Secp256k1.ecdsa_raw_recover('ethereum', [v,r,s])
  end

  def test_ecdsa_sig_serialize
    sig = Secp256k1.sign(Utils.zpad('ethereum', 32), "\x01"*32)
    v, r, s = Secp256k1.ecdsa_raw_sign("ethereum", "\x01"*32)
    assert_equal sig, Secp256k1.ecdsa_sig_serialize(r, s)
  end

end
