# -*- encoding : ascii-8bit -*-

require 'fileutils'

module Ethereum
  module Tester
    class State

      TMP_DIR_PREFIX = 'eth-tester-'.freeze

      attr :env, :block, :blocks

      def initialize(env: nil, num_accounts: Fixture::NUM_ACCOUNTS)
        if env
          @db = env.db
          @env = env
        else
          @db = DB::EphemDB.new
          @env = Env.new @db
        end

        @temp_data_dir = Dir.mktmpdir TMP_DIR_PREFIX

        @block = Block.genesis @env, start_alloc: get_start_alloc(num_accounts)
        @block.timestamp = 1410973349
        @block.coinbase = Fixture.accounts[0]
        @block.gas_limit = 10**9

        @blocks = [@block]
        @last_tx = nil

        ObjectSpace.define_finalizer(self) {|id| FileUtils.rm_rf(@temp_data_dir) }
      end

      def contract(code, sender: Fixture.keys[0], endowment: 0, language: :serpent,
                   libraries: nil, path: nil, constructor_call: nil, **kwargs)
        code = Language.format_spaces code
        compiler = Language.get language

        bytecode = compiler.compile code, path: path, libraries: libraries, **kwargs
        bytecode += constructor_call if constructor_call

        address = evm bytecode, sender: sender, endowment: endowment
        raise AssertError, "Contract code empty" if @block.get_code(address).empty?

        address
      end

      def abi_contract(code, sender: Fixture.keys[0], endowment: 0, language: :serpent,
                       libraries: nil, path: nil, constructor_parameters: nil,
                       log_listener: nil, listen: true, **kwargs)
        code = Language.format_spaces code
        compiler = Language.get language

        contract_interface = compiler.mk_full_signature code, path: path, **kwargs
        translator = ABI::ContractTranslator.new contract_interface

        encoded_parameters = constructor_parameters ?
          translator.encode_constructor_arguments(constructor_parameters) :
          nil

        address = contract(code, sender: sender, endowment: endowment, language: language,
                           libraries: libraries, path: path, constructor_call: encoded_parameters,
                           **kwargs)

        ABIContract.new(self, translator, address, listen: listen, log_listener: log_listener)
      end

      def evm(bytecode, sender: Fixture.keys[0], endowment: 0, gas: nil)
        sendnonce = @block.get_nonce PrivateKey.new(sender).to_address

        tx = Transaction.contract sendnonce, Fixture.gas_price, Fixture.gas_limit, endowment, bytecode
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

      def _send_tx(sender, to, value, evmdata: '', funid: nil, abi: nil, profiling: 0)
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
        raise NotImplemented

        serpent = Language.get :serpent
        raise "ruby-serpent not installed" unless serpent

        sendnonce = @block.get_nonce PrivateKey.new(sender).to_address
        evmdata = funid ? serpent.encode_abi(funid, *abi) : serpent.encode_datalist(*data)

        tx = Transaction.new(sendnonce, Fixture.gas_price, Fixture.gas_limit, to, value, evmdata)
        @last_tx = tx
        tx.sign(sender)

        SPV.make_transaction_proof(@block, tx)
      end

      def verifyspv(sender, to, value, data: [], funid: nil, abi: nil, proof: [])
        raise NotImplemented

        serpent = Language.get(:serpent)
        raise "ruby-serpent not installed" unless serpent

        sendnonce = @block.get_nonce PrivateKey.new(sender).to_address
        evmdata = funid ? serpent.encode_abi(funid, *abi) : serpent.encode_datalist(*data)

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
