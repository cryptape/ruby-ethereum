# -*- encoding : ascii-8bit -*-

require 'test_helper'

class TransactionTest < Minitest::Test
  include Ethereum

  def test_sign
    tx = Transaction.new(0, 1, 31415, "\x00"*20, 0, "")
    tx.sign("\x01"*32)
    assert_equal [
      27,
      70011721239254335992234962732673807139656098521717117805596934149023384508204,
      17624540777746785479194051974711071979083475571118607927022572721095387941
    ], [tx.v, tx.r, tx.s]
    assert_equal "\x1ad/\x0e<:\xf5E\xe7\xac\xbd8\xb0rQ\xb3\x99\t\x14\xf1", tx.sender
  end

  def test_full_hash
    tx = Transaction.new(0, 1, 31415, "\x00"*20, 0, "")
    assert_equal "\t\x9cB\x1ahk\x8f\x87\xea\xb1Q!}]\x80\xec+\xd5W\xdaUZ\xc3)\x81\xf5\xc0Y.\xe3\xe9\x7f", tx.full_hash
  end

  def test_creates
    tx = Transaction.new(0, 1, 31415, "\x00"*20, 0, "")
    assert_equal "2\xdc\xab\x0e\xf3\xfb-\xe2\xfc\xe1\xd2\xe0y\x9d6#\x96q\xf0J", tx.sign("\x01"*32).creates
  end

end

class TransactionFixtureTest < Minitest::Test
  include Ethereum

  run_fixtures "TransactionTests", except: /Homestead/

  def on_fixture_test(name, data)
    begin
      rlpdata = Utils.decode_hex data['rlp'][2..-1]
      tx = RLP.decode rlpdata, sedes: Transaction
      blknum = data['blocknumber'].to_i
      tx.check_low_s if blknum >= Env::DEFAULT_CONFIG[:homestead_fork_blknum]
      sender = tx.sender # tx.sender will validate signature
    rescue
      tx = nil
      #STDERR.puts $!
      #STDERR.puts $!.backtrace[0,10].join("\n")
    end

    if data.has_key?('transaction')
      expected_tx = data['transaction']
      assert_equal decode_uint(expected_tx['nonce']), tx.nonce
      assert_equal decode_hex(expected_tx['to']), tx.to
      assert_equal decode_uint(expected_tx['value']), tx.value
      assert_equal decode_hex(Utils.normalize_hex_without_prefix(expected_tx['data'])), tx.data
      assert_equal decode_uint(expected_tx['gasLimit']), tx.startgas
      assert_equal decode_uint(expected_tx['gasPrice']), tx.gasprice
      assert_equal decode_uint(expected_tx['v']), tx.v
      assert_equal decode_uint(expected_tx['r']), tx.r
      assert_equal decode_uint(expected_tx['s']), tx.s

      assert_equal decode_hex(data['sender']), sender
    else
      assert_nil tx
    end
  end

end
