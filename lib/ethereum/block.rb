# -*- encoding : ascii-8bit -*-

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

    class UnknownParentError < StandardError; end
    class UnsignedTransactionError < StandardError; end
    class InvalidNonce < ValidationError; end
    class InsufficientStartGas < ValidationError; end
    class InsufficientBalance < ValidationError; end
    class BlockGasLimitReached < ValidationError; end

    set_serializable_fields(
      header: BlockHeader,
      uncles: RLP::Sedes::CountableList.new(BlockHeader),
      transaction_list: RLP::Sedes::CountableList.new(Transaction)
    )

    class <<self
      ##
      # Assumption: blocks loaded from the db are not manipulated -> can be
      #   cached including hash.
      def find(env, hash)
        raise ArgumentError, "env must be instance of Env" unless env.instance_of?(Env)
        RLP.decode env.db.get(hash), CachedBlock, options: {env: env}
        # TODO: lru cache
      end
    end

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

    def add_refund(x)
      @refunds += x
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
      validate_transaction tx

      logger.debug "apply transaction tx=#{tx.log_dict}"
      increment_nonce tx.sender

      # buy startgas
      delta_balance tx.sender, -tx.startgas*tx.gasprice

      intrinsic_gas = tx.intrinsic_gas_used
      message_gas = tx.startgas - intrinsic_gas
      message_data = VM::CallData.new tx.data.map(&:ord), 0, tx.data.size
      message = VM::Message.new tx.sender, tx.to, tx.value, message_gas, message_data, code_address: tx.to

      #ext = VM::Ext

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

    ##
    # Commit account caches. Write the account caches on the corresponding
    # tries.
    #
    def commit_state
      return if @journal.empty?

      changes = []
      addresses = @caches[:all].keys.sort

      addresses.each do |addr|
        acct = get_account addr

        %i(balance nonce code storage).each do |field|
          if v = @caches[field][acct]
            changes.push [field, addr, v]
            account.send :"#{field}=", v
          end
        end

        t = SecureTrie.new Trie.new(db, acct.storage)
        @caches.fetch("storage:#{addr}", {}).each do |k, v|
          enckey = Utils.zpad Utils.coerce_to_bytes(k), 32
          val = RLP.encode v
          changes.push ['storage', addr, k, v]

          v && v != 0 ? t.update(enckey, val) : t.delete(enckey)
        end

        acct.storage = t.root_hash
        @state.update addr, RLP.encode(acct)
      end
      logger.debug "delta changes=#{changes}"

      reset_cache
      db.put_temporarily "validated:#{full_hash}", '1'
    end

    def account_exists(address)
      address = Utils.normalize_address address
      @state[address].size > 0 || @caches[:all].has_key?(address)
    end

    def add_log(log)
      @logs.push log
      @log_listeners.each {|l| l(log) }
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

    def snapshot
      # TODO
    end

    def revert(mysnapshot)
      # TODO
    end

    ##
    # Get the nonce of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    #
    # @return [Integer] the nonce value
    #
    def get_nonce(address)
      get_account_item address, :nonce
    end

    ##
    # Set the nonce of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    # @param value [Integer] the new nonce
    #
    # @return [Bool] `true` if successful, otherwise `false`
    #
    def set_nonce(address, value)
      set_account_item address, :nonce, value
    end

    ##
    # Increment the nonce of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    #
    # @return [Bool] `true` if successful, otherwise `false`
    #
    def increment_nonce(address)
      if get_nonce(address) == 0
        delta_account_item address, :nonce, config[:account_initial_nonce]+1
      else
        delta_account_item address, :nonce, 1
      end
    end

    ##
    # Get the balance of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    #
    # @return [Integer] balance value
    #
    def get_balance(address)
      get_account_item address, :balance
    end

    ##
    # Set the balance of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    # @param value [Integer] the new balance value
    #
    # @return [Bool] `true` if successful, otherwise `false`
    #
    def set_balance(address, value)
      set_account_item address, :balance, value
    end

    ##
    # Increase the balance of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    # @param value [Integer] can be positive or negative
    #
    # @return [Bool] `true` if successful, otherwise `false`
    #
    def delta_balance(address, value)
      delta_account_item address, :balance, value
    end

    ##
    # Transfer a value between two account balance.
    #
    # @param from [String] the address of the sending account (binary or hex
    #   string)
    # @param to [String] the address of the receiving account (binary or hex
    #   string)
    # @param value [Integer] the (positive) value to send
    #
    # @return [Bool] `true` if successful, otherwise `false`
    #
    def transfer_value(from, to, value)
      raise ArgumentError, "value must be greater than zero" unless value > 0

      delta_balance(from, -value) && delta_balance(to, value)
    end

    ##
    # Get the code of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    #
    # @return [String] account code
    #
    def get_code(address)
      get_account_item address, :code
    end

    ##
    # Set the code of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    # @param value [String] the new code bytes
    #
    # @return [Bool] `true` if successful, otherwise `false`
    #
    def set_code(address, value)
      set_account_item address, :code, value
    end

    ##
    # Get the trie holding an account's storage.
    #
    # @param address [String] the address of the account (binary or hex string)
    #
    # @return [Trie] the storage trie of account
    #
    def get_storage(address)
      storage_root = get_account_item address, :storage
      SecureTrie.new Trie.new(db, storage_root)
    end

    def reset_storage(address)
      set_account_item address, :storage, Constant::BYTE_EMPTY

      cache_key = "storage:#{address}"
      if @caches.has_key?(cache_key)
        @caches[cache_key].each {|k, v| set_and_journal cache_key, k, 0 }
      end
    end

    ##
    # Get a specific item in the storage of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    # @param index [Integer] the index of the requested item in the storage
    #
    # @return [Integer] the value at storage index
    #
    def get_storage_data(address, index)
      address = Utils.normalize_address address

      cache = @caches["storage:#{address}"]
      return cache[index] if cache && cache[index].has_key?(index)

      key = Utils.zpad Utils.coerce_to_bytes(index), 32
      value = get_storage(address)[key]

      value ? RLP.decode(value, Sedes.big_endian_int) : 0
    end

    ##
    # Set a specific item in the storage of an account.
    #
    # @param address [String] the address of the account (binary or hex string)
    # @param index [Integer] the index of the requested item in the storage
    # @param value [Integer] the new value of the item
    #
    def set_storage_data(address, index, value)
      address = Utils.normalize_address address

      cache_key = "storage:#{address}"
      unless @caches.has_key?(cache_key)
        @caches[cache_key] = {}
        set_and_journal :all, address, true
      end

      set_and_journal cache_key, index, value
    end

    ##
    # Serialize an account to a hash with human readable entries.
    #
    # @param address [String] the account address
    # @param with_storage_root [Bool] include the account's storage root
    # @param with_storage [Bool] include the whole account's storage
    #
    # @return [Hash] hash represent the account
    #
    def account_to_dict(address, with_storage_root: false, with_storage: true)
      address = Utils.normalize_address address

      # if there are uncommited account changes the current storage root is
      # meaningless
      raise ArgumentError, "cannot include storage root with uncommited account changes" if with_storage_root && !@journal.empty?

      h = {}
      account = get_account address

      h[:nonce] = (@caches[:nonce][address] || account.nonce).to_s
      h[:balance] = (@caches[:balance][address] || account.balance).to_s

      code = @caches[:code][address] || account.code
      h[:code] = "0x#{Utils.encode_hex code}"

      storage_trie = SecureTrie.new Trie.new(db, account.storage)
      h[:storage_root] = Utils.encode_hex storage_trie.root_hash if with_storage_root
      if with_storage
        h[:storage] = {}
        sh = storage_trie.to_h

        cache = @caches["storage:#{address}"] || {}
        keys = cache.keys.map {|k| Utils.zpad Utils.coerce_to_bytes(k), 32 }

        (sh.keys + keys).each do |k|
          hexkey = "0x#{Utils.encode_hex Utils.zunpad(k)}"

          v = cache[Utils.big_endian_to_int(k)]
          if v && v != 0
            h[:storage][hexkey] = "0x#{Utils.encode_hex Utils.int_to_big_endian(v)}"
          else
            v = sh[k]
            h[:storage][hexkey] = "0x#{Utils.encode_hex RLP.decode(v)}" if v
          end
        end
      end

      h
    end

    ##
    # Return `n` ancestors of this block.
    #
    # @return [Array] array of ancestors in format of `[parent, parent.parent, ...]
    #
    def get_ancestor_list(n)
      raise ArgumentError, "n must be greater or equal than zero" unless n >= 0

      return [] if n == 0 || number == 0
      parent = get_parent
      [parent] + parent.get_ancestor_list(n-1)
    end

    def get_ancestor_hash(n)
      raise ArgumentError, "n must be greater than 0 and less or equal than 256" unless n > 0 && n <= 256

      while @ancestor_hashes.size < n
        if number == @ancestor_hashes.size - 1
          @ancestor_hashes.push nil
        else
          @ancestor_hashes.push self.class.find(env, @ancestor_hashes[-1]).get_parent().full_hash
        end
      end

      @ancestor_hashes[n-1]
    end

    private

    def logger
      Logger['eth.block']
    end

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
        @state = SecureTrie.new PruningTrie.new(db, header._state_root)
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

    def validate_transaction(tx)
      raise UnsignedTransactionError.new(tx) unless tx.sender

      acct_nonce = get_nonce tx.sender
      raise InvalidNonce, "#{tx}: nonce actual: #{tx.nonce} target: #{acct_nonce}" if acct_nonce != tx.nonce

      min_gas = tx.intrinsic_gas_used
      if number >= config[:homestead_fork_blknum]
        raise ValidationError, "invalid s in transaction signature" unless tx.s*2 < Secp256k1::N
        min_gas += Opcodes::CREATE[3] if !tx.to || tx.to == Address::CREATE_CONTRACT
      end
      raise InsufficientStartGas, "#{tx}: startgas actual: #{tx.startgas} target: #{min_gas}"

      total_cost = tx.value + tx.gasprice * tx.startgas
      balance = get_balance tx.sender
      raise InsufficientBalance, "#{tx}: balance actual: #{balance} target: #{total_cost}" if balance < total_cost

      accum_gas = gas_used + tx.startgas
      raise BlockGasLimitReached, "#{tx}: gaslimit actual: #{accum_gas} target: #{gas_limit}" if accum_gas > gas_limit

      true
    end

    def get_parent_header
      raise UnknownParentError, "Genesis block has no parent" if number == 0

      parent_header = BlockHeader.find db, prevhash
      raise UnknownParentError, Utils.encode_hex(prevhash) unless parent_header

      parent_header
    end

    def calc_difficulty(parent, ts)
      config = parent.config
      offset = parent.difficulty / config[:block_diff_factor]

      if parent.number >= config[:homestead_fork_blknum]-1
        sign = [1 - 2 * ((ts - parent.timestamp) / config[:homestead_diff_adjustment_cutoff]), -99].max
      else
        sign = (ts - parent.timestamp) < config[:diff_adjustment_cutoff] ? 1 : -1
      end

      # If we enter a special mode where the genesis difficulty starts off
      # below the minimal difficulty, we allow low-difficulty blocks (this will
      # never happen in the official protocol)
      o = [parent.difficulty + offset*sign, [parent.difficulty, config[:min_diff]].min].max
      period_count = (parent.number + 1) / config[:expdiff_period]
      if period_count >= config[:expdiff_free_periods]
        o = [o + 2**(period_count - config[:expdiff_free_periods]), config[:min_diff]].max
      end

      o
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
      address = Utils.normalize_address address, allow_blank: true
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
    # Get the account with the given address.
    #
    # Note that this method ignores cached account items.
    #
    def get_account(address)
      address = Utils.normalize_address address, allow_blank: true
      rlpdata = @state.get address

      if rlpdata == Trie::BLANK_NODE
        Account.build_blank db, config[:account_initial_nonce]
      else
        RLP.decode(rlpdata, Account, options: {db: db})
      end
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
