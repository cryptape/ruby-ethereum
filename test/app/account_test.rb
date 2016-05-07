# -*- encoding : ascii-8bit -*-

require 'test_helper'

class AppAccountTest < Minitest::Test
  include Ethereum

  def test_account_creation
    assert !account.locked?
    assert_equal privkey, account.privkey
    assert_equal PrivateKey.new(privkey).to_address, account.address
    assert_equal uuid, account.uuid
  end

  def test_locked
    account = App::Account.new keystore

    assert account.locked?
    assert_equal keystore['address'], Utils.encode_hex(account.address)
    assert_equal nil, account.privkey
    assert_equal nil, account.pubkey
    assert_equal uuid, account.uuid

    keystore2 = keystore.dup
    keystore2.delete 'address'
    account = App::Account.new keystore2

    assert account.locked?
    assert_equal nil, account.address
    assert_equal nil, account.privkey
    assert_equal nil, account.pubkey
    assert_equal uuid, account.uuid
  end

  def test_unlocked
    account = App::Account.new keystore
    assert account.locked?

    account.unlock password
    assert !account.locked?
    assert_equal privkey, account.privkey
    assert_equal PrivateKey.new(privkey).to_address, account.address
  end

  def test_unlock_wrong
    account = App::Account.new keystore
    assert account.locked?
    assert_raises(ValueError) { account.unlock('wrongpass') }
    assert account.locked?

    account.unlock(password)
    assert !account.locked?
    account.unlock('wrongpass')
    assert !account.locked?
  end

  def test_lock
    assert !account.locked?
    assert_equal PrivateKey.new(privkey).to_address, account.address
    assert_equal privkey, account.privkey
    assert !account.pubkey.nil?

    account.lock
    assert account.locked?
    assert_equal PrivateKey.new(privkey).to_address, account.address
    assert_equal nil, account.privkey
    assert account.pubkey.nil?
    assert_raises(ValueError) { account.unlock(password + 'fdsa') }
  ensure
    account.unlock(password)
  end

  def test_address
    keystore_wo_address = keystore.dup
    keystore_wo_address.delete 'address'

    account = App::Account.new keystore_wo_address
    assert account.address.nil?

    account.unlock(password)
    account.lock
    assert_equal PrivateKey.new(privkey).to_address, account.address
  end

  def test_dump
    required_keys = %w(crypto version)

    keystore = JSON.load account.dump(true, true)
    assert_equal (required_keys + %w(address id)).sort, keystore.keys.sort
    assert_equal Utils.encode_hex(account.address), keystore['address']
    assert_equal account.uuid, keystore['id']

    keystore = JSON.load account.dump(false, true)
    assert_equal (required_keys + %w(id)).sort, keystore.keys.sort
    assert_equal account.uuid, keystore['id']

    keystore = JSON.load account.dump(true, false)
    assert_equal (required_keys + %w(address)).sort, keystore.keys.sort
    assert_equal Utils.encode_hex(account.address), keystore['address']

    keystore = JSON.load account.dump(false, false)
    assert_equal required_keys.sort, keystore.keys.sort
  end

  def test_uuid_setting
    uuid = account.uuid

    account.uuid = 'asdf'
    assert_equal 'asdf', account.uuid

    account.uuid = nil
    assert account.uuid.nil?
    assert !account.keystore.has_key?(:id)

    account.uuid = uuid
    assert_equal uuid, account.uuid
    assert_equal uuid, account.keystore[:id]
  end

  def test_sign
    tx = Transaction.new 1, 0, 10**6, account.address, 0, ''
    account.sign_tx tx
    assert_equal account.address, tx.sender

    account.lock
    assert_raises(ValueError) { account.sign_tx(tx) }
  ensure
    account.unlock(password)
  end

  private

  def privkey
    @privkey ||= Utils.decode_hex('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
  end

  def password
    @password ||= 'secret'
  end

  def uuid
    @uuid ||= SecureRandom.uuid
  end

  def account
    @account ||= App::Account.create(password, privkey, uuid)
  end

  def keystore
    @keystore ||= JSON.load(account.dump)
  end

end
