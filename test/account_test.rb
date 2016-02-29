# -*- encoding : ascii-8bit -*-

require 'test_helper'

class AccountTest < Minitest::Test
  include Ethereum

  def test_initialize_with_balance
    db = DB::EphemDB.new
    acct = Account.new 2, 99994000000, Trie::BLANK_ROOT, Utils.keccak256(Constant::BYTE_EMPTY), db

    assert_equal 2, acct.nonce
    assert_equal 99994000000, acct.balance
    assert_equal 2, Utils.big_endian_to_int(RLP.decode(RLP.encode(acct))[0])
    assert_equal 99994000000, Utils.big_endian_to_int(RLP.decode(RLP.encode(acct))[1])
  end

end
