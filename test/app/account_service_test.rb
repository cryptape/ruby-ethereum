# -*- encoding : ascii-8bit -*-

require 'test_helper'

class Ethereum::App::AccountService
  def test(method, *args)
    send method, *args
    return nil
  rescue
    return $!
  end
end

class AppAccountServiceTest < Minitest::Test
  include Ethereum

  def setup
    Celluloid.shutdown rescue nil
    Celluloid.boot

    @app = get_app
    @app.start
  end

  def teardown
    @app.stop
    FileUtils.rm_rf @app.config[:accounts][:keystore_dir]
  end

  def test_empty
    s = @app.services.accounts

    assert_equal 0, s.size
    assert_equal 0, s.accounts_with_address.size
    assert_equal 0, s.unlocked_accounts.size
    assert_equal [], s.accounts
  end

  def test_add_account
    s = @app.services.accounts
    assert_equal 0, s.size

    s.add_account account, false
    assert_equal 1, s.size
    assert_equal [account], s.accounts
    assert_equal account, s[account.address]
    assert_equal [account], s.unlocked_accounts
    assert_equal [account], s.accounts_with_address
    assert_equal account, s.get_by_id(account.uuid)
  end

  def test_add_locked_account
    s = @app.services.accounts

    account.lock
    assert !account.address.nil?

    s.add_account account, false
    assert_equal [account], s.accounts
    assert_equal account, s[account.address]
    assert_equal [], s.unlocked_accounts
    assert_equal [account], s.accounts_with_address
    assert_equal account, s.get_by_id(account.uuid)
  ensure
    account.unlock password
    assert_equal [account], s.unlocked_accounts
  end

  def test_add_account_without_address
    s = @app.services.accounts
    account.lock
    address = account.address
    account.instance_variable_set :@address, nil

    s.add_account account, false
    assert_equal [account], s.accounts
    assert_equal [], s.unlocked_accounts
    assert_equal [], s.accounts_with_address
    assert s.test(:[], address).instance_of?(KeyError)
    assert_equal account, s.get_by_id(account.uuid)
  ensure
    account.instance_variable_set :@address, address
    account.unlock password
  end

  def test_add_account_twice
    s = @app.services.accounts
    s.add_account account, false
    assert s.test(:add_account, account, false).instance_of?(ValueError)
    assert_equal 1, s.accounts.size

    begin
      uuid = account.uuid
      account.uuid = nil
      s.add_account account, false
      assert_equal 2, s.size
      assert_equal [account, account], s.accounts
      assert_equal account, s[account.address]
      assert_equal [account, account], s.unlocked_accounts
      assert_equal [account, account], s.accounts_with_address
    ensure
      account.uuid = uuid
    end
  end

  def test_lock_after_adding
    s = @app.services.accounts
    s.add_account account, false
    assert_equal [account], s.unlocked_accounts

    account.lock
    assert_equal [], s.unlocked_accounts

    account.unlock password
    assert_equal [account], s.unlocked_accounts
  ensure
    account.unlock password
  end

  def test_find
    s = @app.services.accounts

    s.add_account account, false
    assert_equal 1, s.size
    assert_equal account, s.find('1')
    assert_equal account, s.find(Utils.encode_hex(account.address))
    assert_equal account, s.find(Utils.encode_hex(account.address).upcase)
    assert_equal account, s.find('0x' + Utils.encode_hex(account.address))
    assert_equal account, s.find('0x' + Utils.encode_hex(account.address).upcase)
    assert_equal account, s.find(account.uuid)
    assert_equal account, s.find(account.uuid.upcase)

    assert s.test(:find, '').instance_of?(ValueError)
    assert s.test(:find, 'aabbcc').instance_of?(ValueError)
    assert s.test(:find, 'ff'*20).instance_of?(ValueError)
  end

  def test_store
    s = @app.services.accounts

    account.path = File.join @app.config[:accounts][:keystore_dir], 'account1'
    s.add_account account, true, true
    assert File.exist?(account.path)

    account_reloaded = App::Account.load account.path
    assert !account_reloaded.uuid.nil?
    assert !account_reloaded.address.nil?
    assert_equal account.uuid, account_reloaded.uuid
    assert_equal account.address, account_reloaded.address
    assert_equal account.path, account_reloaded.path
    assert !account.privkey.nil?
    assert account_reloaded.privkey.nil?
  ensure
    account.path = nil
  end

  def test_store_overwrite
    s = @app.services.accounts
    uuid = account.uuid
    account.uuid = nil
    account.path = File.join @app.config[:accounts][:keystore_dir], 'account1'

    account2 = App::Account.new account.keystore
    account2.path = File.join @app.config[:accounts][:keystore_dir], 'account2'

    s.add_account account, true
    assert s.test(:add_account, account, true).instance_of?(IOError)
    s.add_account account2, true
  ensure
    account.uuid = uuid
    account.path = nil
  end

  def test_store_dir
    s = @app.services.accounts

    uuid = account.uuid
    account.uuid = nil

    paths = %w(
      some/sub/dir/account1
      some/sub/dir/account2
      account1
    ).map {|d| File.join @app.config[:accounts][:keystore_dir], d }

    paths.each do |path|
      new_account = App::Account.new account.keystore, nil, path
      s.add_account new_account
    end

    paths.each do |path|
      new_account = App::Account.new account.keystore, nil, path
      assert s.test(:add_account, new_account).instance_of?(IOError)
    end
  ensure
    account.uuid = uuid
  end

  def test_store_private
    s = @app.services.accounts

    account.path = File.join @app.config[:accounts][:keystore_dir], 'account1'
    s.add_account account, true, false, false

    account_reloaded = App::Account.load account.path
    assert account_reloaded.address.nil?
    assert account_reloaded.uuid.nil?

    account_reloaded.unlock password
    assert_equal account.address, account_reloaded.address
    assert account_reloaded.uuid.nil?
  ensure
    account.path = nil
  end

  def test_store_absolute
    s = @app.services.accounts

    tmpdir = Dir.mktmpdir('reth-test-store-absolute-')
    account.path = File.join tmpdir, 'account1'

    s.add_account account
    assert File.exist?(account.path)

    account_reloaded = App::Account.load account.path
    assert_equal account.address, account_reloaded.address
  ensure
    FileUtils.rm_rf tmpdir
    account.path = nil
  end

  def test_restart_service
    s = @app.services.accounts

    account.path = File.join @app.config[:accounts][:keystore_dir], 'account1'
    s.add_account account

    @app.deregister_service App::AccountService
    App::AccountService.register_with_app @app
    @app.start

    s = @app.services.accounts
    assert_equal 1, s.size

    reloaded_account = s.accounts[0]
    assert_equal account.path, reloaded_account.path
  end

  def test_account_sorting
    keystore_dummy = {}
    paths = %w(
      /absolute/path/b
      /absolute/path/c
      /absolute/path/letter/e
      /absolute/path/letter/d
      /letter/f
      /absolute/path/a
    ) + [nil]
    paths.sort_by! {|path| path.to_s }

    s = @app.services.accounts
    paths.each do |path|
      s.add_account App::Account.new(keystore_dummy, nil, path), false
    end

    assert_equal paths, s.accounts.map(&:path)
    assert_equal paths, (1..paths.size).map {|i| s.find(i.to_s).path }
  end

  def test_update
    s = @app.services.accounts

    path = File.join @app.config[:accounts][:keystore_dir], 'update_test'
    address = account.address
    privkey = account.privkey
    pubkey = account.pubkey
    uuid = account.uuid
    assert s.test(:update_account, account, 'pw2').instance_of?(ValueError)

    s.add_account account, false
    assert s.test(:update_account, account, 'pw2').instance_of?(ValueError)
    s.accounts.delete account

    account.path = path
    s.add_account account, true
    account.lock
    assert s.test(:update_account, account, 'pw2').instance_of?(ValueError)

    account.unlock password
    s.update_account account, 'pw2'

    assert_equal path, account.path
    assert_equal address, account.address
    assert_equal privkey, account.privkey
    assert_equal pubkey, account.pubkey
    assert_equal uuid, account.uuid
    assert !account.locked?
    assert s.accounts.include?(account)

    account.lock
    assert s.test(:update_account, account, password).instance_of?(ValueError)
    account.unlock 'pw2'
    assert !account.locked?
  ensure
    s.update_account account, password
    account.path = nil
  end

  def test_coinbase
    s = @app.services.accounts
    assert_equal App::AccountService::DEFAULT_COINBASE, s.coinbase

    # coinbase from first account
    s.add_account account, false
    @app.config[:accounts][:must_include_coinbase] = true
    assert_equal account.address, s.coinbase
    @app.config[:accounts][:must_include_coinbase] = false
    assert_equal account.address, s.coinbase

    # coinbase configured
    @app.config[:pow] = {coinbase_hex: Utils.encode_hex(account.address)}
    @app.config[:accounts][:must_include_coinbase] = true
    assert_equal account.address, s.coinbase
    @app.config[:accounts][:must_include_coinbase] = false
    assert_equal account.address, s.coinbase

    [123, "\x00"*20, "\x00"*40, '', 'aabbcc', 'aa'*19, 'ff'*21].each do |invalid|
      @app.config[:pow] = {coinbase_hex: invalid}
      @app.config[:accounts][:must_include_coinbase] = false
      assert s.test(:coinbase).instance_of?(ValueError)
      @app.config[:accounts][:must_include_coinbase] = true
      assert s.test(:coinbase).instance_of?(ValueError)
    end

    ['00'*20, 'ff'*20, '0x' + 'aa'*20].each do |valid|
      @app.config[:pow] = {coinbase_hex: valid}
      @app.config[:accounts][:must_include_coinbase] = false
      assert_equal Utils.decode_hex(Utils.remove_0x_head(valid)), s.coinbase
      @app.config[:accounts][:must_include_coinbase] = true
      assert s.test(:coinbase).instance_of?(ValueError)
    end
  end

  private

  def get_app
    app = DEVp2p::BaseApp.new(accounts: {keystore_dir: Dir.mktmpdir('reth-test-')})
    App::AccountService.register_with_app app
    app
  end

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
