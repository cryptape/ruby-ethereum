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
    def_delegators :@block, :get_code, :get_balance, :set_balance, :get_storage_data, :set_storage_data, :add_refund, :account_exists

    def initialize(block, tx)
      @block = block
      @tx = tx
    end

    def log_storage(x)
      @block.account_to_dict(x)[:storage]
    end

    def add_suicide(x)
      @block.suicides.push x
    end

    def block_hash(x)
      d = @block.number - x
      if d > 0 && d <= 256
        @block.get_ancestor_hash d
      else
        Constant::BYTE_EMPTY
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

    def post_homestead_hardfork
      @block.number >= @block.config[:homestead_fork_blknum]
    end

    def create(msg)
      sender = Utils.normalize_address(msg.sender, allow_blank: true)

      @block.increment_nonce msg.sender if tx_origin != msg.sender

      nonce = Utils.encode_int(@block.get_nonce(msg.sender) - 1)
      msg.to = Utils.mk_contract_address sender, nonce

      balance = get_balance(msg.to)
      if balance > 0
        set_balance msg.to, balance
        @block.set_nonce msg.to, 0
        @block.set_code msg.to, Constant::BYTE_EMPTY
        @block.reset_storage msg.to
      end

      msg.is_create = true

      code = msg.data.extract_all
      msg.data = VM::CallData.new [], 0, 0

      res, gas, dat = apply_msg msg, code

      if res.true?
        return 1, gas, msg.to if dat.empty?

        gcost = dat.size * Opcodes::GCONTRACTBYTE
        if gas >= gcost
          gas -= gcost
        else
          dat = []

          if @block.number >= @block.config[:homestead_fork_blknum]
            return 0, 0, Constant::BYTE_EMPTY
          end

          log_msg.debug "CONTRACT creation oog have=#{gas} want=#{gcost}"
        end

        @block.set_code msg.to, Utils.int_array_to_bytes(dat)
        return 1, gas, msg.to
      else
        return 0, gas, Constant::BYTE_EMPTY
      end
    end

    def apply_msg(msg, code=nil)
      code ||= get_code msg.code_address

      log_msg.debug "MSG APPLY",  sender: Utils.encode_hex(msg.sender), to: Utils.encode_hex(msg.to), gas: msg.gas, value: msg.value, data: Utils.encode_hex(msg.data.extract_all)
      log_state.trace "MSG PRE STATE SENDER", account: msg.sender, balance: get_balance(msg.sender), state: log_storage(msg.sender)
      log_state.trace "MSG PRE STATE RECIPIENT", account: msg.to, balance: get_balance(msg.to), state: log_storage(msg.to)

      # snapshot before execution
      snapshot = @block.snapshot

      # transfer value
      unless @block.transfer_value(msg.sender, msg.to, msg.value)
        log_msg.debug "MSG transfer failed have=#{get_balance(msg.to)} want=#{msg.value}"
        return [1, msg.gas, []]
      end

      # main loop
      if SpecialContract[msg.code_address]
        res, gas, dat = SpecialContract[msg.code_address].call(self, msg)
      else
        res, gas, dat = VM.execute self, msg, code
      end

      log_msg.trace "MSG APPLIED", gas_remained: gas, sender: msg.sender, to: msg.to, data: dat
      log_state.trace "MSG POST STATE SENDER", account: msg.sender, balance: get_balance(msg.sender), state: log_storage(msg.sender)
      log_state.trace "MSG POST STATE RECIPIENT", account: msg.to, balance: get_balance(msg.to), state: log_storage(msg.to)

      if res == 0
        log_msg.debug 'REVERTING'
        @block.revert snapshot
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
