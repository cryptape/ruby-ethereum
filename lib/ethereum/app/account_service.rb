# -*- encoding : ascii-8bit -*-

require 'fileutils'

module Ethereum
  module App

    class AccountService < DEVp2p::BaseService

      name 'accounts'

      default_config(
        accounts: {
          keystore_dir: 'keystore',
          must_include_coinbase: true
        }
      )

      attr :accounts

      DEFAULT_COINBASE = Utils.decode_hex('de0b295669a9fd93d5f28d9ec85e40f4cb697bae')

      def initialize(app)
        super(app)

        if app.config[:accounts][:keystore_dir][0] == '/'
          @keystore_dir = app.config[:accounts][:keystore_dir]
        else # relative path
          @keystore_dir = File.join app.config[:data_dir], app.config[:accounts][:keystore_dir]
        end

        @accounts = []

        if !File.exist?(@keystore_dir)
          logger.warn "keystore directory does not exist", directory: @keystore_dir
        elsif !File.directory?(@keystore_dir)
          logger.error "configured keystore directory is a file, not a directory", directory: @keystore_dir
        else
          logger.info "searching for key files", directory: @keystore_dir

          ignore = %w(. ..)
          Dir.foreach(@keystore_dir) do |filename|
            next if ignore.include?(filename)

            begin
              @accounts.push Account.load(File.join(@keystore_dir, filename))
            rescue ValueError
              logger.warn "invalid file skipped in keystore directory", path: filename
            end
          end
        end
        @accounts.sort_by! {|acct| acct.path.to_s }

        if @accounts.empty?
          logger.warn "no accounts found"
        else
          logger.info "found account(s)", accounts: @accounts
        end
      end

      def _run
        loop do
          sleep 3600
        end
      end

      ##
      # Return the address that should be used as coinbase for new blocks.
      #
      # The coinbase address is given by the config field pow.coinbase_hex. If
      # this does not exist, the address of the first account is used instead.
      # If there are no accounts, the coinbase is `DEFAULT_COINBASE`.
      #
      # @raise [ValueError] if the coinbase is invalid (no string, wrong
      #   length) or there is no account for it and the config flag
      #   `accounts.check_coinbase` is set (does not apply to the default
      #   coinbase).
      #
      def coinbase
        cb_hex = (app.config[:pow] || {})[:coinbase_hex]
        if cb_hex
          raise ValueError, 'coinbase must be String' unless cb_hex.is_a?(String)
          begin
            cb = Utils.decode_hex Utils.remove_0x_head(cb_hex)
          rescue TypeError
            raise ValueError, 'invalid coinbase'
          end
        else
          accts = accounts_with_address
          return DEFAULT_COINBASE if accts.empty?
          cb = accts[0].address
        end

        raise ValueError, 'wrong coinbase length' if cb.size != 20

        if config[:accounts][:must_include_coinbase]
          raise ValueError, 'no account for coinbase' if !@accounts.map(&:address).include?(cb)
        end

        cb
      end

      ##
      # Add an account.
      #
      # If `store` is true the account will be stored as a key file at the
      # location given by `account.path`. If this is `nil` a `ValueError` is
      # raised. `include_address` and `include_id` determine if address and id
      # should be removed for storage or not.
      #
      # This method will raise a `ValueError` if the new account has the same
      # UUID as an account already known to the service. Note that address
      # collisions do not result in an exception as those may slip through
      # anyway for locked accounts with hidden addresses.
      #
      def add_account(account, store=true, include_address=true, include_id=true)
        logger.info "adding account", account: account

        if account.uuid && @accounts.any? {|acct| acct.uuid == account.uuid }
          logger.error 'could not add account (UUID collision)', uuid: account.uuid
          raise ValueError, 'Could not add account (UUID collision)'
        end

        if store
          raise ValueError, 'Cannot store account without path' if account.path.nil?
          if File.exist?(account.path)
            logger.error 'File does already exist', path: account.path
            raise IOError, 'File does already exist'
          end

          raise AssertError if @accounts.any? {|acct| acct.path == account.path }

          begin
            directory = File.dirname account.path
            FileUtils.mkdir_p(directory) unless File.exist?(directory)

            File.open(account.path, 'w') do |f|
              f.write account.dump(include_address, include_id)
            end
          rescue IOError => e
            logger.error "Could not write to file", path: account.path, message: e.to_s
            raise e
          end
        end

        @accounts.push account
        @accounts.sort_by! {|acct| acct.path.to_s }
      end

      ##
      # Replace the password of an account.
      #
      # The update is carried out in three steps:
      #
      # 1. the old keystore file is renamed
      # 2. the new keystore file is created at the previous location of the old
      #   keystore file
      # 3. the old keystore file is removed
      #
      # In this way, at least one of the keystore files exists on disk at any
      # time and can be recovered if the process is interrupted.
      #
      # @param account [Account] which must be unlocked, stored on disk and
      #   included in `@accounts`
      # @param include_address [Bool] forwarded to `add_account` during step 2
      # @param include_id [Bool] forwarded to `add_account` during step 2
      #
      # @raise [ValueError] if the account is locked, if it is not added to the
      #   account manager, or if it is not stored
      #
      def update_account(account, new_password, include_address=true, include_id=true)
        raise ValueError, "Account not managed by account service" unless @accounts.include?(account)
        raise ValueError, "Cannot update locked account" if account.locked?
        raise ValueError, 'Account not stored on disk' unless account.path

        logger.debug "creating new account"
        new_account = Account.create new_password, account.privkey, account.uuid, account.path

        backup_path = account.path + '~'
        i = 1
        while File.exist?(backup_path)
          backup_path = backup_path[0, backup_path.rindex('~')+1] + i.to_s
          i += 1
        end
        raise AssertError if File.exist?(backup_path)

        logger.info 'moving old keystore file to backup location', from: account.path, to: backup_path
        begin
          FileUtils.mv account.path, backup_path
        rescue
          logger.error "could not backup keystore, stopping account update", from: account.path, to: backup_path
          raise $!
        end
        raise AssertError unless File.exist?(backup_path)
        raise AssertError if File.exist?(new_account.path)
        account.path = backup_path

        @accounts.delete account
        begin
          add_account new_account, include_address, include_id
        rescue
          logger.error 'adding new account failed, recovering from backup'
          FileUtils.mv backup_path, new_account.path
          account.path = new_account.path
          @accounts.push account
          @accounts.sort_by! {|acct| acct.path.to_s }
          raise $!
        end
        raise AssertError unless File.exist?(new_account.path)

        logger.info "deleting backup of old keystore", path: backup_path
        begin
          FileUtils.rm backup_path
        rescue
          logger.error 'failed to delete no longer needed backup of old keystore', path: account.path
          raise $!
        end

        account.keystore = new_account.keystore
        account.path = new_account.path

        @accounts.push account
        @accounts.delete new_account
        @accounts.sort_by! {|acct| acct.path.to_s }

        logger.debug "account update successful"
      end

      def accounts_with_address
        @accounts.select {|acct| acct.address }
      end

      def unlocked_accounts
        @accounts.select {|acct| !acct.locked? }
      end

      ##
      # Find an account by either its address, its id, or its index as string.
      #
      # Example identifiers:
      #
      # - '9c0e0240776cfbe6fa1eb37e57721e1a88a563d1' (address)
      # - '0x9c0e0240776cfbe6fa1eb37e57721e1a88a563d1' (address with 0x prefix)
      # - '01dd527b-f4a5-4b3c-9abb-6a8e7cd6722f' (UUID)
      # - '3' (index)
      #
      # @param identifier [String] the accounts hex encoded, case insensitive
      #   address (with optional 0x prefix), its UUID or its index (as string,
      #   >= 1)
      #
      # @raise [ValueError] if the identifier could not be interpreted
      # @raise [KeyError] if the identified account is not known to the account
      #   service
      #
      def find(identifier)
        identifier = identifier.downcase

        if identifier =~ /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ # uuid
          return get_by_id(identifier)
        end

        begin
          address = Address.new(identifier).to_bytes
          raise AssertError unless address.size == 20
          return self[address]
        rescue
          # do nothing
        end

        index = identifier.to_i
        raise ValueError, 'Index must be 1 or greater' if index <= 0
        raise KeyError if index > @accounts.size
        @accounts[index-1]
      end

      ##
      # Return the account with a given id.
      #
      # Note that accounts are not required to have an id.
      #
      # @raise [KeyError] if no matching account can be found
      #
      def get_by_id(id)
        accts = @accounts.select {|acct| acct.uuid == id }

        if accts.size == 0
          raise KeyError, "account with id #{id} unknown"
        elsif accts.size > 1
          logger.warn "multiple accounts with same UUID found", uuid: id
        end

        accts[0]
      end

      ##
      # Get an account by its address.
      #
      # Note that even if an account with the given address exists, it might
      # not be found if it is locked. Also, multiple accounts with the same
      # address may exist, in which case the first one is returned (and a
      # warning is logged).
      #
      # @raise [KeyError] if no matching account can be found
      #
      def get_by_address(address)
        raise ArgumentError, 'address must be 20 bytes' unless address.size == 20

        accts = @accounts.select {|acct| acct.address == address }

        if accts.size == 0
          raise KeyError, "account not found by address #{Utils.encode_hex(address)}"
        elsif accts.size > 1
          logger.warn "multiple accounts with same address found", address: Utils.encode_hex(address)
        end

        accts[0]
      end

      def sign_tx(address, tx)
        get_by_address(address).sign_tx(tx)
      end

      def propose_path(address)
        File.join @keystore_dir, Utils.encode_hex(address)
      end

      def include?(address)
        raise ArgumentError, 'address must be 20 bytes' unless address.size == 20
        @accounts.any? {|acct| acct.address == address }
      end

      def [](address_or_idx)
        if address_or_idx.instance_of?(String)
          raise ArgumentError, 'address must be 20 bytes' unless address_or_idx.size == 20
          acct = @accounts.find {|acct| acct.address == address_or_idx }
          acct or raise KeyError
        else
          raise ArgumentError, 'address_or_idx must be String or Integer' unless address_or_idx.is_a?(Integer)
          @accounts[address_or_idx]
        end
      end

      include Enumerable
      def each(&block)
        @accounts.each(&block)
      end

      def size
        @accounts.size
      end

      def test(method, *args)
        send method, *args
        return nil
      rescue
        return $!
      end

      private

      def logger
        @logger ||= Logger.new('accounts')
      end

    end

  end
end
