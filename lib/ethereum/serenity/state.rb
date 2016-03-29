# -*- encoding : ascii-8bit -*-

module Ethereum
  ##
  # An object representing the state. In serenity, the state will be just a
  # trie of accounts with storage; ALL intermediate state, including gas used,
  # logs, transaction index, etc., is placed into contracts. This greatly
  # simplifies a large amount of handling code.
  #
  class State

    include Constant
    include Config

    def initialize(state_root, db)
      @db = db

      @state = Trie.new db
      @state.set_root_hash state_root

      # The state uses a journaling cache data structure in order to facilitate
      # revert operations while maintaining very high efficiency for updates.
      # Note that the cache is designed to handle commits happening at any
      # time; commits can be reverted too. Committing is done automatically
      # whenever a root is requested; for this reason, use the State.root
      # method to get the root instead of poking into State.state.root_hash
      # directly.
      @journal = []
      @cache = Hash.new {|h, k| h[k] = {} }
      @modified = Hash.new {|h, k| h[k] = {} }
    end

    def set_gas_limit(gas_limit, left_bound=0)
      set_storage Utils.shardify(EXECUTION_STATE, left_bound), GAS_REMAINING, gas_limit
    end

    def root
      commit
      @state.root_hash
    end

    def clone
      commit
      self.class.new @state.root_hash, DB::OverlayDB.new(@state.db)
    end

    def get_storage(addr, k)
      k = Utils.zpad_int(k) if k.is_a?(Integer)
      addr = Utils.normalize_address addr

      return @cache[addr][k] if @cache[addr].has_key?(k)

      t = Trie.new @state.db
      t.set_root_hash @state[addr]

      v = t[k]
      @cache[addr][k] = v
      v
    end

    def set_storage(addr, k, v)
      k = Utils.zpad_int(k) if k.is_a?(Integer)
      v = Utils.zpad_int(v) if v.is_a?(Integer)

      addr = Utils.normalize_address addr
      @journal.push [addr, k, get_storage(addr, k)]
      @cache[addr][k] = v
      @modified[addr][k] = true
    end

    def commit
      root = @state.root_hash

      @cache.each do |addr, cache|
        t = Trie.new @state.db
        t.set_root_hash @state[addr]
        modified = false

        cache.each do |k, v|
          if @modified[addr].has_key?(k) && v != t[k]
            t[k] = v
            modified = true
          end
        end

        @state[addr] = t.root_hash if modified
      end

      @journal.push ['~root', [@cache, @modified], root]
      @cache = Hash.new {|h, k| h[k] = {} }
      @modified = Hash.new {|h, k| h[k] = {} }
    end

    def to_h
      state_dump = {}

      @state.to_h.each do |address, acct_root|
        acct_dump = {}
        acct_trie = Trie.new @state.db
        acct_trie.set_root_hash acct_root

        acct_trie.each do |k, v|
          acct_dump[Utils.encode_hex(k)] = Utils.encode_hex(v)
        end

        state_dump[Utils.encode_hex(address)] = acct_dump
      end

      @cache.each do |address, cache|
        key = Utils.encode_hex address
        state_dump[key] = {} unless state_dump.has_key?(key)

        cache.each do |k, v|
          state_dump[key][Utils.encode_hex(k)] = Utils.encode_hex(v) if v.true?
        end

        state_dump.delete(key) if state_dump[key].false?
      end

      state_dump
    end

    def account_to_h(account)
      addr = Utils.normalize_address account
      acct_trie = Trie.new @state.db
      acct_trie.set_root_hash @state[addr]

      acct_dump = {}
      acct_trie.each do |k, v|
        acct_dump[Utils.encode_hex(k)] = Utils.encode_hex(v)
      end

      if @cache.has_key?(addr)
        @cache[addr].each do |k, v|
          if v.true?
            acct_dump[k] = v
          else
            acct_dump.delete k if acct_dump.has_key?(k)
          end
        end
      end

      acct_dump
    end

    ##
    # Returns a value x, where State#revert at any later point will return you
    # to the point at which the snapshot was made.
    #
    def snapshot
      @journal.size
    end

    def revert(snapshot)
      while @journal.size > snapshot
        addr, key, preval = @journal.pop
        if addr == '~root'
          @state.set_root_hash = preval
          @cache, @modified = key
        else
          @cache[addr][key] = preval
        end
      end
    end

  end
end
