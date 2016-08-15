# -*- encoding : ascii-8bit -*-

require 'fileutils'

module Ethereum
  module Tester
    class State

      TMP_DIR_PREFIX = 'eth-tester-'.freeze

      attr :block, :blocks

      def initialize(num_accounts=Fixture::NUM_ACCOUNTS)
        @temp_data_dir = Dir.mktmpdir TMP_DIR_PREFIX

        @db = DB::EphemDB.new
        @env = Env.new @db

        @block = Block.genesis @env, start_alloc: get_start_alloc(num_accounts)
        @block.timestamp = 1410973349
        @block.coinbase = Fixture.accounts[0]
        @block.gas_limit = 10**9

        @blocks = [@block]
        @last_tx = nil

        ObjectSpace.define_finalizer(self) {|id| FileUtils.rm_rf(@temp_data_dir) }
      end

      def contract(code, sender: Fixture.keys[0], endowment: 0, language: :serpent, gas: nil)
        code = Language.format_spaces code
        opcodes = Language.get(language).compile(code)
        addr = evm(opcodes, sender: sender, endowment: endowment)
        raise AssertError, "Contract code empty" if @block.get_code(addr).empty?
        addr
      end

      def abi_contract(code, **kwargs)
        sender        = kwargs.delete(:sender) || Fixture.keys[0]
        endowment     = kwargs.delete(:endowment) || 0
        language      = kwargs.delete(:language) || :serpent
        contract_name = kwargs.delete(:contract_name) || ''
        gas           = kwargs.delete(:gas) || nil
        log_listener  = kwargs.delete(:log_listener) || nil
        listen        = kwargs.delete(:listen) || true

        code = Language.format_spaces code
        lang = Language.get language
        opcodes = lang.compile code, **kwargs
        addr = evm(opcodes, sender: sender, endowment: endowment, gas: gas)
        raise AssertError, "Contract code empty" if @block.get_code(addr).empty?

        abi = lang.mk_full_signature(code, **kwargs)
        ABIContract.new(self, abi, addr, listen: listen, log_listener: log_listener)
      end

      def evm(opcodes, sender: Fixture.keys[0], endowment: 0, gas: nil)
        sendnonce = @block.get_nonce PrivateKey.new(sender).to_address

        tx = Transaction.contract sendnonce, Fixture.gas_price, Fixture.gas_limit, endowment, opcodes
        tx.sign sender
        tx.startgas = gas if gas

        success, output = @block.apply_transaction tx
        raise ContractCreationFailed if success.false?

        output
      end

      def call(*args, **kwargs)
        raise DeprecatedError, "Call deprecated. Please use the abi_contract mechanism or message(sender, to, value, data) directly, using the ABI module to generate data if needed."
      end

      def send_tx(*args, **kwargs)
        _send_tx(*args, **kwargs)[:output]
      end

      def _send_tx(sender, to, value, evmdata: '', output: nil, funid: nil, abi: nil, profiling: 0)
        if funid || abi
          raise ArgumentError, "Send with funid+abi is deprecated. Please use the abi_contract mechanism."
        end

        t1, g1 = Time.now, @block.gas_used
        sendnonce = @block.get_nonce PrivateKey.new(sender).to_address
        tx = Transaction.new(sendnonce, Fixture.gas_price, Fixture.gas_limit, to, value, evmdata)
        @last_tx = tx
        tx.sign(sender)

        recorder = profiling > 1 ? LogRecorder.new : nil

        success, output = @block.apply_transaction(tx)
        raise TransactionFailed if success.false?
        out = {output: output}

        if profiling > 0
          zero_bytes = tx.data.count Constant::BYTE_ZERO
          none_zero_bytes = tx.data.size - zero_bytes
          intrinsic_gas_used = Opcodes::GTXCOST +
            Opcodes::GTXDATAZERO * zero_bytes +
            Opcodes::GTXDATANONZERO * none_zero_bytes
          t2, g2 = Time.now, @block.gas_used
          out[:time] = t2 - t1
          out[:gas] = g2 - g1 - intrinsic_gas_used
        end

        if profiling > 1
          # TODO: collect all traced ops use LogRecorder
        end

        out
      end

      def profile(*args, **kwargs)
        kwargs[:profiling] = true
        _send_tx(*args, **kwargs)
      end

      def mkspv(sender, to, value, data: [], funid: nil, abi: nil)
        sendnonce = @block.get_nonce PrivateKey.new(sender).to_address
        evmdata = funid ? Serpent.encode_abi(funid, *abi) : Serpent.encode_datalist(*data)

        tx = Transaction.new(sendnonce, Fixture.gas_price, Fixture.gas_limit, to, value, evmdata)
        @last_tx = tx
        tx.sign(sender)

        SPV.make_transaction_proof(@block, tx)
      end

      def verifyspv(sender, to, value, data: [], funid: nil, abi: nil, proof: [])
        sendnonce = @block.get_nonce PrivateKey.new(sender).to_address
        evmdata = funid ? Serpent.encode_abi(funid, *abi) : Serpent.encode_datalist(*data)

        tx = Transaction.new(sendnonce, Fixture.gas_price, Fixture.gas_limit, to, value, evmdata)
        @last_tx = tx
        tx.sign(sender)

        SPV.verify_transaction_proof(@block, tx, proof)
      end

      def trace(sender, to, value, data=[])
        recorder = LogRecorder.new
        send_tx sender, to, value, data
        recorder.pop_records # TODO: implement recorder
      end

      def mine(n=1, coinbase: Fixture.accounts[0])
        n.times do |i|
          @block.finalize
          @block.commit_state

          @db.put @block.full_hash, RLP.encode(@block)

          t = @block.timestamp + 6 + rand(12)
          x = Block.build_from_parent @block, coinbase, timestamp: t
          @block = x

          @blocks.push @block
        end
      end

      def snapshot
        RLP.encode @block
      end

      def revert(data)
        @block = RLP.decode data, sedes: Block, env: @env

        @block.make_mutable!
        @block._cached_rlp = nil

        @block.header.make_mutable!
        @block.header._cached_rlp = nil
      end

      private

      def get_start_alloc(num_accounts)
        o = {}
        num_accounts.times {|i| o[Fixture.accounts[i]] = {wei: 10**24} }
        (1...5).each {|i| o[Utils.int_to_addr(i)] = {wei: 1} }
        o
      end

    end
  end
end
