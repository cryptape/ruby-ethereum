# -*- encoding : ascii-8bit -*-

require 'forwardable'

module Ethereum
  class FastVM

    class Call

      include Constant
      include Config

      extend Forwardable
      def_delegators :@state, :set_storage, :get_storage, :unhash, :puthashdata

      class <<self
        def cache
          @cache ||= {}
        end
      end

      def initialize(state, listeners: [])
        @state = state
        @listeners = listeners
      end

      def log_storage(account)
        @state.account_to_h(account)
      end

      def unhash(x)
        @state
      end

      def apply_msg(msg, code, breaking: false)
        c_sender_ether = Utils.match_shard ETHER, msg.sender
        c_recipient_ether = Utils.match_shard ETHER, msg.to

        cache_key = "#{msg.sender}#{msg.to}#{msg.value}#{msg.data.extract_all}#{code}"
        return Call.cache[cache_key] if self == StaticCall.instance && Call.cache.has_key?(cache_key)

        # Transfer value, instaquit if not enough
        snapshot = @state.snapshot
        if msg.transfers_value
          if Utils.big_endian_to_int(get_storage(c_sender_ether, msg.sender)) < msg.value
            puts "MSG TRANSFER FAILED"
            return [1, msg.gas, []]
          elsif msg.value.true?
            sender_balance = Utils.big_endian_to_int get_storage(c_sender_ether, msg.sender)
            set_storage c_sender_ether, msg.sender,  sender_balance-msg.value

            recipient_balance = Utils.big_endian_to_int get_storage(c_recipient_ether, msg.to)
            set_storage c_recipient_ether, msg.to, recipient_balance+msg.value
          end
        end

        # Main loop
        msg_to_raw = Utils.big_endian_to_int msg.to
        if SpecialContract[msg_to_raw]
          res, gas, dat = SpecialContract[msg_to_raw].call self, msg
        else
          res, gas, dat = VM.execute self, msg, code, breaking: breaking
        end

        if res == 0
          puts "REVERTING #{msg.gas} gas from account 0x#{Utils.encode_hex(msg.sender)} to account 0x#{Utils.encode_hex(msg.to)} with data 0x#{Utils.encode_hex(msg.data.extract_all)}"
          @state.revert(snapshot)
        else
          #puts "MSG APPLY SUCCESSFUL"
        end

        result = [res, (res.true? ? gas : 0), dat]
        Call.cache[cache_key] = result
        result
      end

      def static_msg(msg, code)
        StaticCall.instance.apply_msg msg, code
      end

    end

    class StaticCall < Call

      def self.instance
        @instance ||= new
      end

      def initialize
        @state = ::Ethereum::State.new Trie::BLANK_NODE, DB::EphemDB.new
      end

      def set_storage(*args)
        # do nothing
      end

      def get_storage(*args)
        BYTE_EMPTY
      end

      def log(topics, mem)
        # do nothing
      end

      def log_storage(addr)
        # do nothing
      end

      def unhash(x)
        BYTE_EMPTY
      end
    end

  end
end
