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
        end
      end

      def initialize(keystore, password=nil, path=nil)
        @keystore = keystore
        @address = keystore[:address] ? Utils.decode_hex(keystore[:address]) : nil

        @path = path
        @locked = true

        unlock(password) if password
      end

      private

      def logger
        @logger ||= Logger.new('accounts')
      end

    end

  end
end
