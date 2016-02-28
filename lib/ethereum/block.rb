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

    HeaderGetters = (BlockHeader.serializable_fields.keys - %i(state_root receipts_root tx_list_root)).freeze
    HeaderSetters = HeaderGetters.map {|field| :"#{field}=" }.freeze

    extend Forwardable
    def_delegators :header, *HeaderGetters, *HeaderSetters

    class UnknownParentError < StandardError; end
    class UnsignedTransactionError < StandardError; end
    class InvalidNonce < ValidationError; end
    class InvalidUncles < ValidationError; end
    class InsufficientStartGas < ValidationError; end
    class InsufficientBalance < ValidationError; end
    class BlockGasLimitReached < ValidationError; end
    class BlockVerificationError < ValidationError; end

    set_serializable_fields(
      header: BlockHeader,
      transaction_list: RLP::Sedes::CountableList.new(Transaction),
      uncles: RLP::Sedes::CountableList.new(BlockHeader)
    )

    class <<self
      ##
      # Assumption: blocks loaded from the db are not manipulated -> can be
      #   cached including hash.
      def find(env, hash)
        raise ArgumentError, "env must be instance of Env" unless env.instance_of?(Env)
        RLP.decode env.db.get(hash), CachedBlock, options: {env: env}
      end
      lru_cache :find, 1024

      ##
      # Create a block without specifying transactions or uncles.
      #
      # @param header_rlp [String] the RLP encoded block header
      # @param env [Env] provide database for the block
      #
      # @return [Block]
      #
      def build_from_header(header_rlp, env)
        header = RLP.decode header_rlp, sedes: BlockHeader
        new header, transaction_list: nil, uncles: [], env: env
      end

      ##
      # Create a new block based on a parent block.
      #
      # The block will not include any transactions and will not be finalized.
      #
      def build_from_parent(parent, coinbase, nonce: Constant::BYTE_EMPTY, extra_data: Constant::BYTE_EMPTY, timestamp: Time.now.to_i, uncles: [], env: nil)
        env ||= parent.env

        header = BlockHeader.new(
          prevhash: parent.full_hash,
          uncles_hash: Utils.keccak256_rlp(uncles),
          coinbase: coinbase,
          state_root: parent.state_root,
          tx_list_root: Trie::BLANK_ROOT,
          receipts_root: Trie::BLANK_ROOT,
          bloom: 0,
          difficulty: calc_difficulty(parent, timestamp),
          mixhash: Constant::BYTE_EMPTY,
          number: parent.number+1,
          gas_limit: calc_gaslimit(parent),
          gas_used: 0,
          timestamp: timestamp,
          extra_data: extra_data,
          nonce: nonce
        )

        Block.new(
          header,
          transaction_list: [],
          uncles: uncles,
          env: env,
          parent: parent,
          making: true
        ).tap do |blk|
          blk.ancestor_hashes = [parent.hash] + parent.ancestor_hashes
          blk.log_listeners = parent.log_listeners
        end
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

      def calc_gaslimit(parent)
        config = parent.config
        decay = parent.gas_limit / config[:gaslimit_ema_factor]
        new_contribution = ((parent.gas_used * config[:blklim_factor_nom]) / config[:blklim_factor_den] / config[:gaslimit_ema_factor])

        gl = [parent.gas_limit - decay + new_contribution, config[:min_gas_limit]].max
        if gl < config[:genesis_gas_limit]
          gl2 = parent.gas_limit + decay
          gl = [config[:genesis_gas_limit], gl2].min
        end
        raise ValueError, "invalid gas limit" unless check_gaslimit(parent, gl)

        gl
      end

      def check_gaslimit(parent, gas_limit)
        config = parent.config
        adjmax = parent.gas_limit / config[:gaslimit_adjmax_factor]
        (gas_limit - parent.gas_limit).abs <= adjmax && gas_limit >= parent.config[:min_gas_limit]
      end

      ##
      # Build the genesis block.
      #
      def genesis(env, options={})
        allowed_args = %i(start_alloc prevhash coinbase difficulty gas_limit timestamp extra_data mixhash nonce)
        invalid_options = options.keys - allowed_args
        raise ArgumentError, "invalid options: #{invalid_options}" unless invalid_options.empty?

        start_alloc = options[:start_alloc] || env.config[:genesis_initial_alloc]

        header = BlockHeader.new(
          prevhash: options[:prevhash] || env.config[:genesis_prevhash],
          uncles_hash: Utils.keccak256_rlp([]),
          coinbase: options[:coinbase] || env.config[:genesis_coinbase],
          state_root: Trie::BLANK_ROOT,
          tx_list_root: Trie::BLANK_ROOT,
          receipts_root: Trie::BLANK_ROOT,
          bloom: 0,
          difficulty: options[:difficulty] || env.config[:genesis_difficulty],
          number: 0,
          gas_limit: options[:gas_limit] || env.config[:genesis_gas_limit],
          timestamp: options[:timestamp] || 0,
          extra_data: options[:extra_data] || env.config[:genesis_extra_data],
          mixhash: options[:mixhash] || env.config[:genesis_mixhash],
          nonce: options[:nonce] || env.config[:genesis_nonce]
        )

        block = Block.new header, transaction_list: [], uncles: [], env: env

        start_alloc.each do |addr, data|
          addr = Utils.normalize_address addr

          block.set_balance addr, data[:wei] if data[:wei]
          block.set_balance addr, data[:balance] if data[:balance]
          block.set_code addr, data[:code] if data[:code]
          block.set_nonce addr, data[:nonce] if data[:nonce]

          if data[:storage]
            data[:storage].each {|k, v| block.set_storage_data addr, k, v }
          end
        end

        block.commit_state
        block.state.db.commit

        # genesis block has predefined state root (so no additional
        # finalization necessary)
        block
      end
    end

    attr :env, :db, :config
    attr_accessor :ancestor_hashes, :log_listeners

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
      self.log_listeners = []

      @refunds = 0
      @ether_delta = 0

      self.ancestor_hashes = number > 0 ? [prevhash] : [nil]*256

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

      validate_block!(original_values)
      unless db.has_key?("validated:#{full_hash}")
        if number == 0
          db.put "validated:#{full_hash}", '1'
        else
          db.put_temporarily "validated:#{full_hash}", '1'
        end
      end

      header.block = self
      header.instance_variable_set :@_mutable, original_values[:header_mutable]
    end

    ##
    # The binary block hash. This is equivalent to `header.full_hash`.
    #
    def full_hash
      Utils.keccak256_rlp header
    end

    ##
    # The hex encoded block hash. This is equivalent to `header.hex_full_hash`.
    #
    def hex_full_hash
      Utils.encode_hex full_hash
    end

    def tx_list_root
      @transactions.root_hash
    end

    def tx_list_root=(v)
      @transactions = PruningTrie.new db, v
    end

    def receipts_root
      @receipts.root_hash
    end

    def receipts_root=(v)
      @receipts = PruningTrie.new db, v
    end

    def state_root
      commit_state
      @state.root_hash
    end

    def state_root=(v)
      @state = SecureTrie.new PruningTrie.new(db, v)
      reset_cache
    end

    def uncles_hash
      Utils.keccak256_rlp uncles
    end

    def transaction_list
      @transaction_count.times.map {|i| get_transaction(i) }
    end

    ##
    # Validate the uncles of this block.
    #
    def validate_uncles
      return false if uncles.size > config[:max_uncles]

      uncles.each do |uncle|
        raise InvalidUncles, "Cannot find uncle prevhash in db" unless db.include?(uncle.prevhash)
        if uncle.number == number
          logger.error "uncle at same block height block=#{self}"
          return false
        end
      end

      max_uncle_depth = config[:max_uncle_depth]
      ancestor_chain = [self] + get_ancestor_list(max_uncle_depth+1)
      raise ValueError, "invalid ancestor chain" unless ancestor_chain.size == [number+1, max_uncle_depth+2].min

      # Uncles of this block cannot be direct ancestors and cannot also be
      # uncles included 1-6 blocks ago.
      ineligible = []
      ancestor_chain[1..-1].each {|a| ineligible.concat a.uncles }
      ineligible.concat(ancestor_chain.map {|a| a.header })

      eligible_ancestor_hashes = ancestor_chain[2..-1].map(&:full_hash)

      uncles.each do |uncle|
        parent = Block.find env, uncle.prevhash
        return false if uncle.difficulty != Block.calc_difficulty(parent, uncle.timestamp)
        return false unless uncle.check_pow

        unless eligible_ancestor_hashes.include?(uncle.prevhash)
          logger.error "Uncle does not have a valid ancestor block=#{self} eligible=#{eligible_ancestor_hashes.map {|h| Utils.encode_hex(h) }} uncle_prevhash=#{Utils.encode_hex uncle.prevhash}"
          return false
        end

        if ineligible.include?(uncle)
          logger.error "Duplicate uncle block=#{self} uncle=#{Utils.encode_hex Utils.keccak256_rlp(uncle)}"
          return false
        end

        ineligible.push uncle
      end

      true
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
    # Get the `num`th transaction in this block.
    #
    # @raise [IndexError] if the transaction does not exist
    #
    def get_transaction(num)
      index = RLP.encode num
      tx = @transactions.get index

      raise IndexError, "Transaction does not exist" if tx == Trie::BLANK_NODE
      RLP.decode tx, sedes: Transaction
    end

    ##
    # Build a list of all transactions in this block.
    #
    def get_transactions
      # FIXME: such memoization is potentially buggy - what if pop b from and
      # push a to the cache? size will not change while content changed.
      if @get_transactions_cache.size != @transaction_count
        @get_transactions_cache = transaction_list
      end

      @get_transactions_cache
    end

    ##
    # helper to check if block contains a tx.
    #
    def get_transaction_hashes
      @transaction_count.times.map do |i|
        Utils.keccak256 @transactions[RLP.encode(i)]
      end
    end

    def include_transaction?(tx_hash)
      raise ArgumentError, "argument must be transaction hash in bytes" unless tx_hash.size == 32
      get_transaction_hashes.include?(tx_hash)
    end

    def transaction_count
      @transaction_count
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

        t = SecureTrie.new PruningTrie.new(db, acct.storage)
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
      log_listeners.each {|l| l(log) }
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

    ##
    # Make a snapshot of the current state to enable later reverting.
    #
    def snapshot
      { state: state.root_hash,
        gas: gas_used,
        txs: @transactions,
        txcount: @transaction_count,
        refunds: @refunds,
        suicides: @suicides,
        suicides_size: @suicides.size,
        logs: @logs,
        logs_size: @logs.size,
        journal: @journal, # pointer to reference, so is not static
        journal_size: @journal.size,
        ether_delta: @ether_delta
      }
    end

    ##
    # Revert to a previously made snapshot.
    #
    # Reverting is for example neccessary when a contract runs out of gas
    # during execution.
    #
    def revert(mysnapshot)
      logger.debug "REVERTING"

      @journal = mysnapshot[:journal]
      # if @journal changed after snapshot
      while @journal.size > mysnapshot[:journal_size]
        cache, index, prev, post = @journal.pop
        logger.debug "revert journal cache=#{cache} index=#{index} prev=#{prev} post=#{post}"
        if prev
          @caches[cache][index] = prev
        else
          @caches[cache].delete index
        end
      end

      @suicides = mysnapshot[:suicides]
      @suicides.pop while @suicides.size > mysnapshot[:suicides_size]

      @logs = mysnapshot[:logs]
      @logs.pop while @logs.size > mysnapshot[:logs_size]

      @refunds = mysnapshot[:refunds]
      @state.root_hash = mysnapshot[:state]
      @gas_used = mysnapshot[:gas]
      @transactions = mysnapshot[:txs]
      @transaction_count = mysnapshot[:txcount]
      @ether_delta = mysnapshot[:ether_delta]

      @get_transactions_cache = []
    end

    ##
    # Get the receipt of the `num`th transaction.
    #
    # @raise [IndexError] if receipt at index is not found
    #
    # @return [Receipt]
    #
    def get_receipt(num)
      index = RLP.encode num
      receipt = @receipts[index]

      if receipt == Trie::BLANK_NODE
        raise IndexError, "Receipt does not exist"
      else
        RLP.decode receipt, Receipt
      end
    end

    ##
    # Build a list of all receipts in this block.
    #
    def get_receipts
      receipts = []
      i = 0
      loop do
        begin
          receipts.push get_receipt(i)
        rescue IndexError
          return receipts
        end
      end
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
      SecureTrie.new PruningTrie.new(db, storage_root)
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

      storage_trie = SecureTrie.new PruningTrie.new(db, account.storage)
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

      while ancestor_hashes.size < n
        if number == ancestor_hashes.size - 1
          ancestor_hashes.push nil
        else
          ancestor_hashes.push self.class.find(env, ancestor_hashes[-1]).get_parent().full_hash
        end
      end

      ancestor_hashes[n-1]
    end

    def genesis?
      number == 0
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
        @transaction_count = 0 # TODO - should always equal @transactions.size
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
      raise ValidationError, "Block's gaslimit is inconsistent with its parent's gaslimit" unless Block.check_gaslimit(parent, gas_limit)
      raise ValidationError, "Block's difficulty is inconsistent with its parent's difficulty" if difficulty != Block.calc_difficulty(parent, timestamp)
      raise ValidationError, "Gas used exceeds gas limit" if gas_used > gas_limit
      raise ValidationError, "Timestamp equal to or before parent" if timestamp <= parent.timestamp
      raise ValidationError, "Timestamp way too large" if timestamp > Constant::UINT_MAX
    end

    def validate_block!(original_values)
      raise BlockVerificationError, "gas_used mistmatch actual: #{gas_used} target: #{original_values[:gas_used]}" if gas_used != original_values[:gas_used]
      raise BlockVerificationError, "timestamp mistmatch actual: #{timestamp} target: #{original_values[:timestamp]}" if timestamp != original_values[:timestamp]
      raise BlockVerificationError, "difficulty mistmatch actual: #{difficulty} target: #{original_values[:difficulty]}" if difficulty != original_values[:difficulty]
      raise BlockVerificationError, "bloom mistmatch actual: #{bloom} target: #{original_values[:bloom]}" if bloom != original_values[:bloom]

      uh = Utils.keccak256 RLP.encode(uncles)
      raise BlockVerificationError, "uncles_hash mistmatch actual: #{uh} target: #{original_values[:uncles_hash]}" if uh != original_values[:uncles_hash]

      raise BlockVerificationError, "header must reference no block" unless header.block.nil?

      raise BlockVerificationError, "state_root mistmatch actual: #{@state.root_hash} target: #{header.state_root}" if @state.root_hash != header.state_root
      raise BlockVerificationError, "tx_list_root mistmatch actual: #{@transactions.root_hash} target: #{header.tx_list_root}" if @transactions.root_hash != header.tx_list_root
      raise BlockVerificationError, "receipts_root mistmatch actual: #{@receipts.root_hash} target: #{header.receipts_root}" if @receipts.root_hash != header.receipts_root

      #raise ValueError, "Block is invalid" unless validate_fields # TODO: uncomment to see if tests break

      raise ValueError, "Extra data cannot exceed #{config[:max_extradata_length]} bytes" if header.extra_data.size > config[:max_extradata_length]
      raise ValueError, "Coinbase cannot be empty address" if header.coinbase.nil? || header.coinbase.empty?
      raise ValueError, "State merkle root of block #{self} not found in database" unless @state.root_hash_valid?
      raise ValueError, "PoW check failed" unless genesis? || nonce.nil? || header.check_pow
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

    ##
    # Check that the values of all fields are well formed.
    #
    # Serialize and deserialize and check that the values didn't change.
    #
    def validate_fields
      RLP.decode(RLP.encode(self)) == self
    end

    def get_parent_header
      raise UnknownParentError, "Genesis block has no parent" if number == 0

      parent_header = BlockHeader.find db, prevhash
      raise UnknownParentError, Utils.encode_hex(prevhash) unless parent_header

      parent_header
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
