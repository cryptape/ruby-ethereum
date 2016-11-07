# -*- encoding : ascii-8bit -*-

require 'forwardable'

module Ethereum

  ##
  # External calls that can be made from inside the VM. To use the EVM with a
  # different blockchain system, database, set parameters for testing, just
  # swap out the functions here.
  #
  class ExternalCall

    extend Forwardable
    def_delegators :@block, :get_code, :set_code, :get_balance, :set_balance,
      :delta_balance, :get_nonce, :set_nonce, :increment_nonce,
      :get_storage_data, :set_storage_data, :get_storage_bytes, :reset_storage,
      :add_refund, :add_touched, :add_suicide,
      :account_exists, :account_is_empty, :account_is_dead,
      :snapshot, :revert, :transfer_value, :post_hardfork?

    def initialize(block, tx)
      @block = block
      @tx = tx
    end

    def log_storage(x)
      @block.account_to_dict(x)[:storage]
    end

    def block_hash(x)
      if post_hardfork?(:metropolis)
        get_storage_data @block.config[:metropolis_blockhash_store], x
      else
        d = @block.number - x
        hash = if d > 0 && d <= 256
                 @block.get_ancestor_hash d
               else
                 Constant::BYTE_EMPTY
               end
        Utils.big_endian_to_int hash
      end
    end

    def block_coinbase
      @block.coinbase
    end

    def block_timestamp
      @block.timestamp
    end

    def block_number
      @block.number
    end

    def block_difficulty
      @block.difficulty
    end

    def block_gas_limit
      @block.gas_limit
    end

    def log(addr, topics, data)
      @block.add_log Log.new(addr, topics, data)
    end

    def tx_origin
      @tx.sender
    end

    def tx_gasprice
      @tx.gasprice
    end

    def create(msg)
      log_msg.debug 'CONTRACT CREATION'

      sender = Utils.normalize_address(msg.sender, allow_blank: true)

      code = msg.data.extract_all
      if post_hardfork?(:metropolis)
        msg.to = Utils.mk_metropolis_contract_address msg.sender, code
        if get_code(msg.to)
          n1 = get_nonce msg.to
          n2 = n1 >= Constant::TT40 ?
            (n + 1) :
            (Utils.big_endian_to_int(msg.to) + 2)
          set_nonce msg.to, (n2 % Constant::TT160)
          msg.to = Utils.normalize_address((get_nonce(msg.to) - 1) % Constant::TT160)
        end
      else
        increment_nonce msg.sender if tx_origin != msg.sender

        nonce = Utils.encode_int(get_nonce(msg.sender) - 1)
        msg.to = Utils.mk_contract_address sender, nonce
      end

      balance = get_balance(msg.to)
      if balance > 0
        set_balance msg.to, balance
        set_nonce msg.to, @block.config[:account_initial_nonce]
        set_code msg.to, Constant::BYTE_EMPTY
        reset_storage msg.to
      end

      msg.is_create = true
      msg.data = VM::CallData.new [], 0, 0

      snapshot = self.snapshot
      increment_nonce msg.to if post_hardfork?(:spurious_dragon)
      res, gas, dat = apply_msg msg, code

      if res.true?
        return 1, gas, msg.to if dat.empty?

        gcost = dat.size * Opcodes::GCONTRACTBYTE
        if gas >= gcost
          gas -= gcost
        else
          dat = []
          log_msg.debug "CONTRACT CREATION OOG", have: gas, want: gcost, block_number: @block.number

          if post_hardfork?(:homestead)
            revert snapshot
            return 0, 0, Constant::BYTE_EMPTY
          end
        end

        set_code msg.to, Utils.int_array_to_bytes(dat)
        return 1, gas, msg.to
      else
        revert snapshot if post_hardfork?(:homestead)
        return 0, gas, Constant::BYTE_EMPTY
      end
    end

    def apply_msg(msg, code=nil)
      code ||= get_code msg.code_address

      if log_msg.trace?
        log_msg.debug "MSG APPLY",  sender: Utils.encode_hex(msg.sender), to: Utils.encode_hex(msg.to), gas: msg.gas, value: msg.value, data: Utils.encode_hex(msg.data.extract_all)
        if log_state.trace?
          log_state.trace "MSG PRE STATE SENDER", account: Utils.encode_hex(msg.sender), balance: get_balance(msg.sender), state: log_storage(msg.sender)
          log_state.trace "MSG PRE STATE RECIPIENT", account: Utils.encode_hex(msg.to), balance: get_balance(msg.to), state: log_storage(msg.to)
        end
      end

      # snapshot before execution
      snapshot = self.snapshot

      # transfer value
      if msg.transfers_value
        unless transfer_value(msg.sender, msg.to, msg.value)
          log_msg.debug "MSG TRANSFER FAILED", have: get_balance(msg.to), want: msg.value
          return [1, msg.gas, []]
        end
      end

      # main loop
      if SpecialContract[msg.code_address]
        res, gas, dat = SpecialContract[msg.code_address].call(self, msg)
      else
        res, gas, dat = VM.execute self, msg, code
      end

      if log_msg.trace?
        log_msg.trace "MSG APPLIED", gas_remained: gas, sender: msg.sender, to: msg.to, data: dat
        if log_state.trace?
          log_state.trace "MSG POST STATE SENDER", account: Utils.encode_hex(msg.sender), balance: get_balance(msg.sender), state: log_storage(msg.sender)
          log_state.trace "MSG POST STATE RECIPIENT", account: Utils.encode_hex(msg.to), balance: get_balance(msg.to), state: log_storage(msg.to)
        end
      end

      if res == 0
        log_msg.debug 'REVERTING'
        revert snapshot
      end

      if post_hardfork?(:spurious_dragon)
        add_touched msg.to if msg.value == 0
      end

      return res, gas, dat
    end

    private

    def log_msg
      @log_msg ||= Logger.new 'eth.external_call.msg'
    end

    def log_state
      @log_state ||= Logger.new 'eth.external_call.state'
    end

  end

end
