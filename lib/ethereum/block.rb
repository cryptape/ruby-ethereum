require 'forwardable'

module Ethereum

  ##
  # A block.
  #
  # All attributes from the block header are accessible via properties (i.e.
  # `block.prevhash` is equivalent to `block.header.prevhash`). It is ensured
  # that no discrepancies between header and the block occur.
  #
  class Block
    include RLP::Sedes::Serializable

    HeaderGetters = (BlockHeader.serializable_fields.keys - %i(state_root receipts_root tx_list_root) + %i(full_hash hex_full_hash)).freeze
    HeaderSetters = HeaderGetters.map {|field| :"#{field}=" }.freeze

    extend Forwardable
    def_delegators :header, *HeaderGetters, *HeaderSetters

    class ValidationError < StandardError; end
    class UnknownParentException < StandardError; end

    set_serializable_fields(
      header: BlockHeader,
      uncles: RLP::Sedes::CountableList.new(BlockHeader),
      transaction_list: RLP::Sedes::CountableList.new(Transaction)
    )

    attr :db, :config

    ##
    # @param header [BlockHeader] the block header
    # @param transaction_list [Array[Transaction]] a list of transactions which
    #   are replayed if the state given by the header is not known. If the state
    #   is known, `nil` can be used instead of the empty list.
    # @param uncles [Array[BlockHeader]] a list of the headers of the uncles of
    #   this block
    # @param env [Env] env including db in which the block's state,
    #   transactions and receipts are stored (required)
    # @param parent [Block] optional parent which if not given may have to be
    #   loaded from the database for replay
    def initialize(header, transaction_list: [], uncles: [], env: nil, parent: nil, making: false)
      raise ArgumentError, "No Env object given" unless env.instance_of?(Env)
      raise ArgumentError, "No database object given" unless env.db.is_a?(DB::BaseDB)

      @env = env
      @db = env.db
      @config = env.config

      _set_field :header, header
      _set_field :uncles, uncles

      reset_cache
      @get_transactions_cache = []

      @suicides = []
      @logs = []
      @log_listeners = []

      @refunds = 0
      @ether_delta = 0

      @ancestor_hashes = number > 0 ? [prevhash] : [nil]*256

      validate_parent!(parent) if parent

      original_values = {
        bloom: bloom,
        gas_used: gas_used,
        timestamp: timestamp,
        difficulty: difficulty,
        uncles_hash: uncles_hash,
        header_mutable: header.mutable?
      }

      @_mutable = true
      header.instance_variable_set :@_mutable, true

      @transactions = PruningTrie.new db
      @receipts = PruningTrie.new db

      initialize_state(transaction_list, parent, making)

      # TODO: more
    end

    ##
    # Add a transaction to the transaction trie.
    #
    # Note that this does not execute anything, i.e. the state is not updated.
    #
    def add_transaction_to_list(tx)
      k = RLP.encode @transaction_count
      @transactions[k] = RLP.encode(tx)

      r = mk_transaction_receipt tx
      @receipts[k] = RLP.encode(r)

      @bloom |= r.bloom
      @transaction_count += 1
    end

    def apply_transaction(tx)
      # TODO
    end

    ##
    # Apply rewards and commit.
    #
    def finalize
      delta = @config[:block_reward] + @config[:nephew_reward] * uncles.size

      delta_balance coinbase, delta
      @ether_delta += delta

      uncles.each do |uncle|
        r = @config[:block_reward] * (@config[:uncle_depth_penalty_factor] + uncle.number - number) / @config[:uncle_depth_penalty_factor]

        delta_balance coinbase, r
        @ether_delta += r
      end

      commit_state
    end

    def commit_state
      # TODO
    end

    ##
    # Increase the balance of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    # @param value [Integer] can be positive or negative
    #
    # @return [Bool] return `true` if successful, otherwise `false`
    #
    def delta_balance(address, value)
      delta_account_item(address, :balance, value)
    end

    def state_root
      commit_state
      @state.root_hash
    end

    def state_root=(v)
      @state = SecureTrie.new PruningTrie.new(db, v)
      reset_cache
    end

    ##
    # Reset cache and journal without commiting any changes.
    #
    def reset_cache
      @caches = {
        all: {},
        balance: {},
        nonce: {},
        code: {},
        storage: {}
      }
      @journal = []
    end

    private

    def initialize_state(transaction_list, parent, making)
      state_unknown =
        prevhash != @config[:genesis_prevhash] &&
        number != 0 &&
        header.state_root != PruningTrie::BLANK_ROOT &&
        (header.state_root.size != 32 || !db.has_key?("validated:#{full_hash}")) &&
        !making

      if state_unknown
        raise ArgumentError, "transaction list cannot be nil" unless transaction_list

        parent ||= get_parent_header
        @state = SecureTrie.new PruningTrie.new(db, parent.state_root)
        @transaction_count = 0
        @gas_used = 0

        transaction_list.each {|tx| apply_transaction tx }

        finalize
      else # trust the state root in the header
        @state = SecureTrie.new PruningTrie.new(db, header.instance_variable_get(:@state_root))
        @transaction_count = 0

        transaction_list.each {|tx| add_transaction_to_list(tx) } if transaction_list
        raise ValidationError, "Transaction list root hash does not match" if @transactions.root_hash != header.tx_list_root

        # receipts trie populated by add_transaction_to_list is incorrect (it
        # doesn't know intermediate states), so reset it
        @receipts = PruningTrie.new db, header.receipts_root
      end
    end

    def validate_parent!(parent)
      raise ValidationError, "Parent lives in different database" if parent && db != parent.db && db.db != parent.db # TODO: refactor the db.db mess
      raise ValidationError, "Block's prevhash and parent's hash do not match" if prevhash != parent.full_hash
      raise ValidationError, "Block's number is not the successor of its parent number" if number != parent.number+1
      raise ValidationError, "Block's gaslimit is inconsistent with its parent's gaslimit" unless valid_gas_limit?(parent, gas_limit)
      raise ValidationError, "Block's difficulty is inconsistent with its parent's difficulty" if difficulty != calc_difficulty(parent, timestamp)
      raise ValidationError, "Gas used exceeds gas limit" if gas_used > gas_limit
      raise ValidationError, "Timestamp equal to or before parent" if timestamp <= parent.timestamp
      raise ValidationError, "Timestamp way too large" if timestamp > Constant::UINT_MAX
    end

    def valid_gas_limit?(parent, gl)
      adjmax = parent.gas_limit / parent.config[:gaslimit_adjmax_factor]
      (gl - parent.gas_limit).abs <= adjmax && gl >= parent.config[:min_gas_limit]
    end

    def get_parent_header
      raise UnknownParentException, "Genesis block has no parent" if number == 0

      parent_header = get_block_header prevhash
      raise UnknownParentException, Utils.encode_hex(prevhash) unless parent_header

      parent_header
    end

    def get_block_header(blockhash)
      bh = BlockHeader.from_block_rlp db.get(blockhash)
      raise ValidationError, "BlockHeader.hash is broken" if bh.full_hash != blockhash
      bh
    end

    def calc_difficulty(parent, ts)
      # TODO
    end

    ##
    # Add a value to an account item.
    #
    # If the resulting value would be negative, it is left unchanged and
    # `false` is returned.
    #
    # @param address [String] the address of the account (binary or hex string)
    # @param param [Symbol] the parameter to increase or decrease (`:nonce`,
    #   `:balance`, `:storage`, or `:code`)
    # @param value [Integer] can be positive or negative
    #
    # @return [Bool] `true` if the operation was successful, `false` if not
    #
    def delta_account_item(address, param, value)
      new_value = get_account_item(address, param) + value
      return false if new_value < 0

      set_account_item(address, param, new_value % 2**256)
      true
    end

    ##
    # Get a specific parameter of a specific account.
    #
    # @param address [String] the address of the account (binary or hex string)
    # @param param [Symbol] the requested parameter (`:nonce`, `:balance`,
    #   `:storage` or `:code`)
    #
    # @return [Object] the value
    #
    def get_account_item(address, param)
      raise ArgumentError, "invalid address: #{address}" unless address.size == 0 || address.size == 20 || address.size == 40
      address = Utils.decode_hex(address) if address.size == 40

      return @caches[param][address] if @caches[param].has_key?(address)

      account = get_account address
      v = account.send param
      @caches[param][address] = v
      v
    end

    ##
    # Set a specific parameter of a specific account.
    #
    # @param address [String] the address of the account (binary or hex string)
    # @param param [Symbol] the requested parameter (`:nonce`, `:balance`,
    #   `:storage` or `:code`)
    # @param value [Object] the new value
    #
    def set_account_item(address, param, value)
      raise ArgumentError, "invalid address: #{address}" unless address.size == 20 || address.size == 40
      address = Utils.decode_hex(address) if address.size == 40

      set_and_journal(param, address, value)
      set_and_journal(:all, address, true)
    end

    ##
    # @param ns [Symbol] cache namespace
    # @param k [String] cache key
    # @param v [Object] cache value
    #
    def set_and_journal(ns, k, v)
      prev = @caches[ns][k]
      if prev != v
        @journal.append [ns, k, prev, v]
        @caches[ns][k] = v
      end
    end

    def mk_transaction_receipt(tx)
      Receipt.new state_root, gas_used, @logs
    end

  end
end
