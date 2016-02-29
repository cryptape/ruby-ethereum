# -*- encoding : ascii-8bit -*-

module Ethereum

  ##
  # An Ethereum account.
  #
  # * `@nonce`: the account's nonce (the number of transactions sent by the
  #   account)
  # * `@balance`: the account's balance in wei
  # * `@storage`: the root of the account's storage trie
  # * `@code_hash`: the SHA3 hash of the code associated with the account
  # * `@db`: the database in which the account's code is stored
  #
  class Account
    include RLP::Sedes::Serializable

    set_serializable_fields(
      nonce: Sedes.big_endian_int,
      balance: Sedes.big_endian_int,
      storage: Sedes.trie_root,
      code_hash: Sedes.hash32
    )

    class <<self
      ##
      # Create a blank account.
      #
      # The returned account will have zero nonce and balance, a blank storage
      # trie and empty code.
      #
      # @param db [BaseDB] the db in which the account will store its code
      #
      # @return [Account] the created blank account
      #
      def build_blank(db, initial_nonce=0)
        code_hash = Utils.keccak256 Constant::BYTE_EMPTY
        db.put code_hash, Constant::BYTE_EMPTY

        new initial_nonce, 0, Trie::BLANK_ROOT, code_hash, db
      end
    end

    def initialize(*args)
      @db = args.pop if args.size == 5 # (nonce, balance, storage, code_hash, db)
      @db = args.last.delete(:db) if args.last.is_a?(Hash)
      raise ArgumentError, "No database object given" unless @db.is_a?(DB::BaseDB)

      super(*args)
    end

    ##
    # The EVM code of the account.
    #
    # This property will be read from or written to the db at each access, with
    # `code_hash` used as key.
    #
    def code
      @db.get code_hash
    end

    def code=(value)
      self.code_hash = Utils.keccak256 value

      # Technically a db storage leak, but doesn't really matter; the only
      # thing that fails to get garbage collected is when code disappears due
      # to a suicide.
      @db.inc_refcount(code_hash, value)
    end

  end
end
