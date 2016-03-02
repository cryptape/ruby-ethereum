# -*- encoding : ascii-8bit -*-

require 'test_helper'

class Msg < Struct.new(:gas, :data)
end

class SpecialContractTest < Minitest::Test
  include Ethereum

  def test_identity
    cd = VM::CallData.new Utils.bytes_to_int_array("ethereum")

    msg = Msg.new 0, cd
    assert_equal [0, 0, []], SpecialContract[Utils.zpad_int(4, 20)].call(nil, msg)

    msg = Msg.new 100, cd
    output = Utils.bytes_to_int_array('ethereum')
    assert_equal [1, 82, output], SpecialContract[Utils.zpad_int(4, 20)].call(nil, msg)
  end

  def test_ripemd160
    cd = VM::CallData.new Utils.bytes_to_int_array("ethereum")

    msg = Msg.new 0, cd
    assert_equal [0, 0, []], SpecialContract[Utils.zpad_int(3, 20)].call(nil, msg)

    msg = Msg.new 1000, cd
    output = Utils.bytes_to_int_array Utils.zpad(Utils.ripemd160('ethereum'), 32)
    assert_equal [1, 280, output], SpecialContract[Utils.zpad_int(3, 20)].call(nil, msg)
  end

  def test_sha256
    cd = VM::CallData.new Utils.bytes_to_int_array("ethereum")

    msg = Msg.new 0, cd
    assert_equal [0, 0, []], SpecialContract[Utils.zpad_int(2, 20)].call(nil, msg)

    msg = Msg.new 1000, cd
    output = Utils.bytes_to_int_array Utils.zpad(Utils.sha256('ethereum'), 32)
    assert_equal [1, 928, output], SpecialContract[Utils.zpad_int(2, 20)].call(nil, msg)
  end

  def test_ecrecover
    priv = "\x01"*32
    pub = PrivateKey.new(priv).to_pubkey
    #priv, pub = Secp256k1.generate_key_pair false
    v, r, s = Secp256k1.ecdsa_raw_sign('ethereum', priv)

    sig = Utils.zpad_int(v) + Utils.zpad_int(r) + Utils.zpad_int(s)
    hash = Utils.zpad("ethereum", 32)
    cd = VM::CallData.new Utils.bytes_to_int_array(hash + sig)

    msg = Msg.new 0, cd
    assert_equal [0, 0, []], SpecialContract[Utils.zpad_int(1, 20)].call(nil, msg)

    msg = Msg.new 5000, cd
    pub = PublicKey.new(pub).encode(:bin)
    pubhash = Utils.keccak256(pub[1..-1])[-20..-1]
    output = Utils.bytes_to_int_array Utils.zpad(pubhash, 32)
    assert_equal [1, 2000, output], SpecialContract[Utils.zpad_int(1, 20)].call(nil, msg)
  end

end
