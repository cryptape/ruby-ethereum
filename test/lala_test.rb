# -*- encoding : ascii-8bit -*-

require 'test_helper'

class LalaTest < Minitest::Test
  include Ethereum

  def test_lala
    priv = Utils.decode_hex 'd06ad30da01e9d83a26f41ea39c63323a365ad569a684e43c9983de0d64347d1'
    p priv
    p priv.size
    p Utils.encode_hex(PrivateKey.new(priv).to_pubkey)
    p Address.new(PrivateKey.new(priv).to_address).to_hex
    msg = Utils.decode_hex 'c63ca8231343283681395197b0c35624173d378e83c70720e38a102c0c231812'
    sig = Secp256k1.recoverable_sign msg, priv
    puts "sig"
    p sig
    v, r, s = sig
    p Utils.int_to_big_endian(r).bytes.map(&:ord)
    p Utils.int_to_big_endian(s).bytes.map(&:ord)
    pub = Secp256k1.recover_pubkey msg, sig
    p Utils.encode_hex(pub)
  end

end
