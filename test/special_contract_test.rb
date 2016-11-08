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
    priv = PrivateKey.new("\x01"*32)
    pub = priv.to_pubkey

    msg = Utils.zpad("ethereum", 32)
    v, r, s = Secp256k1.recoverable_sign(msg, priv.encode(:bin))

    sig = Utils.zpad_int(Transaction.encode_v(v)) + Utils.zpad_int(r) + Utils.zpad_int(s)
    cd = VM::CallData.new Utils.bytes_to_int_array(msg + sig)

    msg = Msg.new 0, cd
    assert_equal [0, 0, []], SpecialContract[Utils.zpad_int(1, 20)].call(nil, msg)

    msg = Msg.new 5000, cd
    pub = PublicKey.new(pub).encode(:bin)
    pubhash = Utils.keccak256(pub[1..-1])[-20..-1]
    output = Utils.bytes_to_int_array Utils.zpad(pubhash, 32)
    assert_equal [1, 2000, output], SpecialContract[Utils.zpad_int(1, 20)].call(nil, msg)
  end

end
