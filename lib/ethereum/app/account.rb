# -*- encoding : ascii-8bit -*-

module Ethereum
  module App

    class Account

      class <<self
        ##
        # Create a new account.
        #
        # Note that this creates the account in memory and does not store it on
        # disk.
        #
        # @param password [String] used to encrypt the private key
        # @param key [String] the private key, or `nil` to generate a random one
        # @param uuid [String] an optional id
        #
        def create(password, key=nil, uuid=nil, path=nil)
          key ||= Utils.mk_random_privkey

          json = Keystore.make_json key, password
          json[:id] = uuid

          new json, password, path
        end

        ##
        # Load an account from a keystore file.
        #
        # @param path [String] full path to the keyfile
        # @param password [String] the password to decrypt the key file or
        #   `nil` to leave it encrypted
        #
        def load(path, password=nil)
          json = JSON.load File.read(path)
          raise ValidationError, 'Invalid keystore file' unless Keystore.validate(json)
          new json, password, path
        end
      end

      attr_accessor :path, :address, :keystore

      def initialize(keystore, password=nil, path=nil)
        @keystore = Hashie.symbolize_keys keystore
        @address = keystore[:address] ? Utils.decode_hex(keystore[:address]) : nil

        @path = path
        @locked = true

        unlock(password) if password
      end

      ##
      # Dump the keystore for later disk storage.
      #
      # The result inherits the entries `crypto` and `version` from `Keystore`,
      # and adds `address` and `id` in accordance with the parameters
      # `include_address` and `include_id`.
      #
      # If address or id are not known, they are not added, even if requested.
      #
      # @param include_address [Bool] flag denoting if the address should be
      #   included or not
      # @param include_id [Bool] flag denoting if the id should be included or
      #   not
      #
      def dump(include_address=true, include_id=true)
        h = {}
        h[:crypto] = @keystore[:crypto]
        h[:version] = @keystore[:version]

        h[:address] = Utils.encode_hex address if include_address && address
        h[:id] = uuid if include_id && uuid

        JSON.dump(h)
      end

      ##
      # Unlock the account with a password.
      #
      # If the account is already unlocked, nothing happens, even if the
      # password is wrong.
      #
      # @raise [ValueError] (originating from `Keystore.decode_json`) if the
      # password is wrong and the account is locked
      #
      def unlock(password)
        if @locked
          @privkey = Keystore.decode_json @keystore, password
          @locked = false
          address # get address such that it stays accessible after a subsequent lock
        end
      end

      ##
      # Relock an unlocked account.
      #
      # This method sets `privkey` to `nil` (unlike `address` which is
      # preserved).
      #
      def lock
        @privkey = nil
        @locked = true
      end

      def privkey
        @locked ? nil : @privkey
      end

      def pubkey
        @locked ? nil : PrivateKey.new(@privkey).to_pubkey
      end

      def address
        unless @address
          if @keystore[:address]
            @address = Utils.decode_hex(@keystore[:address])
          elsif !@locked
            @address = PrivateKey.new(@privkey).to_address
          else
            return nil
          end
        end

        @address
      end

      ##
      # An optional unique identifier, formatted according to UUID version 4,
      # or `nil` if the account does not have an id.
      #
      def uuid
        @keystore[:id]
      end

      def uuid=(id)
        if id
          @keystore[:id] = id
        else
          @keystore.delete :id
        end
      end

      ##
      # Sign a Transaction with the private key of this account.
      #
      # If the account is unlocked, this is equivalent to
      # `tx.sign(account.privkey)`.
      #
      # @param tx [Transaction] the transaction to sign
      # @raise [ValueError] if the account is locked
      #
      def sign_tx(tx)
        if privkey
          logger.info "signing tx", tx: tx, account: self
          tx.sign privkey
        else
          raise ValueError, "Locked account cannot sign tx"
        end
      end

      def locked?
        @locked
      end

      def to_s
        addr = address ? Utils.encode_hex(address) : '?'
        "<Account(address=#{addr}, id=#{uuid})>"
      end

      private

      def logger
        @logger ||= Logger.new('accounts')
      end

    end

  end
end
