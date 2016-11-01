# -*- encoding : ascii-8bit -*-

require 'ethereum/vm/call_data'
require 'ethereum/vm/message'
require 'ethereum/vm/state'

module Ethereum
  class VM

    class <<self
      def code_cache
        @code_cache ||= {}
      end

      def execute(*args)
        new.execute(*args)
      end
    end

    include Constant

    def execute(ext, msg, code)
      s = State.new gas: msg.gas

      if VM.code_cache.has_key?(code)
        processed_code = VM.code_cache[code]
      else
        processed_code = preprocess_code code
        VM.code_cache[code] = processed_code
      end

      # for trace only
      steps = 0
      _prevop = nil

      loop do
        return peaceful_exit('CODE OUT OF RANGE', s.gas, []) if s.pc >= processed_code.size

        op, in_args, out_args, fee, opcode, pushval = processed_code[s.pc]

        return vm_exception('OUT OF GAS') if fee > s.gas
        return vm_exception('INSUFFICIENT STACK', op: op, needed: in_args, available: s.stack.size) if in_args > s.stack.size
        return vm_exception('STACK SIZE LIMIT EXCEEDED', op: op, pre_height: s.stack.size) if (s.stack.size - in_args + out_args) > 1024

        s.gas -= fee
        s.pc += 1

        # This diverges from normal logging, as we use the logging namespace
        # only to decide which features get logged in 'eth.vm.op', i.e.
        # tracing can not be activated by activating a sub like
        # 'eth.vm.op.stack'.
        if log_vm_exit.trace?
          trace_data = {
            stack: s.stack.map(&:to_s),
            gas: s.gas + fee,
            inst: opcode,
            pc: s.pc-1,
            op: op,
            steps: steps
          }

          if %i(MLOAD MSTORE MSTORE8 SHA3 CALL CALLCODE CREATE CALLDATACOPY CODECOPY EXTCODECOPY).include?(_prevop)
            if s.memory.size < 1024
              trace_data[:memory] = Utils.encode_hex(Utils.int_array_to_bytes(s.memory))
            else
              trace_data[:sha3memory] = Utils.encode_hex(Utils.keccak256(Utils.int_array_to_bytes(s.memory)))
            end
          end

          if %i(SSTORE SLOAD).include?(_prevop) || steps == 0
            trace_data[:storage] = ext.log_storage(msg.to)
          end

          if steps == 0
            trace_data[:depth] = msg.depth
            trace_data[:address] = msg.to
          end

          if op[0,4] == 'PUSH'
            trace_data[:pushvalue] = pushval
          end

          log_vm_op.trace('vm', **trace_data)

          steps += 1
          _prevop = op
        end

        # Invalid operation
        return vm_exception('INVALID OP', opcode: opcode) if op == :INVALID

        # Valid operations
        stk = s.stack
        mem = s.memory
        if opcode < 0x10 # Stop & Arithmetic Operations
          case op
          when :STOP
            return peaceful_exit('STOP', s.gas, [])
          when :ADD
            r = (stk.pop + stk.pop) & UINT_MAX
            stk.push r
          when :SUB
            r = (stk.pop - stk.pop) & UINT_MAX
            stk.push r
          when :MUL
            r = (stk.pop * stk.pop) & UINT_MAX
            stk.push r
          when :DIV
            s0, s1 = stk.pop, stk.pop
            stk.push(s1 == 0 ? 0 : s0 / s1)
          when :MOD
            s0, s1 = stk.pop, stk.pop
            stk.push(s1 == 0 ? 0 : s0 % s1)
          when :SDIV
            s0, s1 = Utils.to_signed(stk.pop), Utils.to_signed(stk.pop)
            r = s1 == 0 ? 0 : ((s0.abs / s1.abs * (s0*s1 < 0 ? -1 : 1)) & UINT_MAX)
            stk.push r
          when :SMOD
            s0, s1 = Utils.to_signed(stk.pop), Utils.to_signed(stk.pop)
            r = s1 == 0 ? 0 : ((s0.abs % s1.abs * (s0 < 0 ? -1 : 1)) & UINT_MAX)
            stk.push r
          when :ADDMOD
            s0, s1, s2 = stk.pop, stk.pop, stk.pop
            r = s2 == 0 ? 0 : (s0+s1) % s2
            stk.push r
          when :MULMOD
            s0, s1, s2 = stk.pop, stk.pop, stk.pop
            r = s2 == 0 ? 0 : Utils.mod_mul(s0, s1, s2)
            stk.push r
          when :EXP
            base, exponent = stk.pop, stk.pop

            # fee for exponent is dependent on its bytes
            # calc n bytes to represent exponent
            nbytes = Utils.encode_int(exponent).size
            expfee = nbytes * Opcodes::GEXPONENTBYTE
            if s.gas < expfee
              s.gas = 0
              return vm_exception('OOG EXPONENT')
            end

            s.gas -= expfee
            stk.push Utils.mod_exp(base, exponent, TT256)
          when :SIGNEXTEND # extend sign from bytes at s0 to left
            s0, s1 = stk.pop, stk.pop
            if s0 < 32
              testbit = s0*8 + 7
              mask = 1 << testbit
              if s1 & mask == 0 # extend 0s
                stk.push(s1 & (mask - 1))
              else # extend 1s
                stk.push(s1 | (TT256 - mask))
              end
            else
              stk.push s1
            end
          end
        elsif opcode < 0x20 # Comparison & Bitwise Logic Operations
          case op
          when :LT
            s0, s1 = stk.pop, stk.pop
            stk.push(s0 < s1 ? 1 : 0)
          when :GT
            s0, s1 = stk.pop, stk.pop
            stk.push(s0 > s1 ? 1 : 0)
          when :SLT
            s0, s1 = Utils.to_signed(stk.pop), Utils.to_signed(stk.pop)
            stk.push(s0 < s1 ? 1 : 0)
          when :SGT
            s0, s1 = Utils.to_signed(stk.pop), Utils.to_signed(stk.pop)
            stk.push(s0 > s1 ? 1 : 0)
          when :EQ
            s0, s1 = stk.pop, stk.pop
            stk.push(s0 == s1 ? 1 : 0)
          when :ISZERO
            s0 = stk.pop
            stk.push(s0 == 0 ? 1 : 0)
          when :AND
            s0, s1 = stk.pop, stk.pop
            stk.push(s0 & s1)
          when :OR
            s0, s1 = stk.pop, stk.pop
            stk.push(s0 | s1)
          when :XOR
            s0, s1 = stk.pop, stk.pop
            stk.push(s0 ^ s1)
          when :NOT
            s0 = stk.pop
            stk.push(UINT_MAX - s0)
          when :BYTE
            s0, s1 = stk.pop, stk.pop
            if s0 < 32
              stk.push((s1 / 256**(31-s0)) % 256)
            else
              stk.push(0)
            end
          end
        elsif opcode < 0x40 # SHA3 & Environmental Information
          case op
          when :SHA3
            s0, s1 = stk.pop, stk.pop

            s.gas -= Opcodes::GSHA3WORD * (Utils.ceil32(s1) / 32)
            return vm_exception('OOG PAYING FOR SHA3') if s.gas < 0

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, s1)

            data = Utils.int_array_to_bytes mem.safe_slice(s0,s1)
            stk.push Utils.big_endian_to_int(Utils.keccak256(data))
          when :ADDRESS
            stk.push Utils.coerce_to_int(msg.to)
          when :BALANCE
            if ext.post_anti_dos_hardfork
              return vm_exception('OUT OF GAS') unless eat_gas(s, Opcodes::BALANCE_SUPPLEMENTAL_GAS)
            end
            s0 = stk.pop
            addr = Utils.coerce_addr_to_hex(s0 % 2**160)
            stk.push ext.get_balance(addr)
          when :ORIGIN
            stk.push Utils.coerce_to_int(ext.tx_origin)
          when :CALLER
            stk.push Utils.coerce_to_int(msg.sender)
          when :CALLVALUE
            stk.push msg.value
          when :CALLDATALOAD
            stk.push msg.data.extract32(stk.pop)
          when :CALLDATASIZE
            stk.push msg.data.size
          when :CALLDATACOPY
            mstart, dstart, size = stk.pop, stk.pop, stk.pop

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, mstart, size)
            return vm_exception('OOG COPY DATA') unless data_copy(s, size)

            msg.data.extract_copy(mem, mstart, dstart, size)
          when :CODESIZE
            stk.push processed_code.size
          when :CODECOPY
            mstart, cstart, size = stk.pop, stk.pop, stk.pop

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, mstart, size)
            return vm_exception('OOG COPY CODE') unless data_copy(s, size)

            size.times do |i|
              if cstart + i < processed_code.size
                mem[mstart+i] = processed_code[cstart+i][4] # copy opcode
              else
                mem[mstart+i] = 0
              end
            end
          when :GASPRICE
            stk.push ext.tx_gasprice
          when :EXTCODESIZE
            if ext.post_anti_dos_hardfork
              return vm_exception('OUT OF GAS') unless eat_gas(s, Opcodes::EXTCODELOAD_SUPPLEMENTAL_GAS)
            end
            addr = stk.pop
            addr = Utils.coerce_addr_to_hex(addr % 2**160)
            stk.push (ext.get_code(addr) || Constant::BYTE_EMPTY).size
          when :EXTCODECOPY
            if ext.post_anti_dos_hardfork
              return vm_exception('OUT OF GAS') unless eat_gas(s, Opcodes::EXTCODELOAD_SUPPLEMENTAL_GAS)
            end
            addr, mstart, cstart, size = stk.pop, stk.pop, stk.pop, stk.pop
            addr = Utils.coerce_addr_to_hex(addr % 2**160)
            extcode = ext.get_code(addr) || Constant::BYTE_EMPTY
            raise ValueError, "extcode must be string" unless extcode.is_a?(String)

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, mstart, size)
            return vm_exception('OOG COPY CODE') unless data_copy(s, size)

            size.times do |i|
              if cstart + i < extcode.size
                mem[mstart+i] = extcode[cstart+i].ord
              else
                mem[mstart+i] = 0
              end
            end
          end
        elsif opcode < 0x50 # Block Information
          case op
          when :BLOCKHASH
            s0 = stk.pop
            stk.push ext.block_hash(s0)
          when :COINBASE
            stk.push Utils.big_endian_to_int(ext.block_coinbase)
          when :TIMESTAMP
            stk.push ext.block_timestamp
          when :NUMBER
            stk.push ext.block_number
          when :DIFFICULTY
            stk.push ext.block_difficulty
          when :GASLIMIT
            stk.push ext.block_gas_limit
          end
        elsif opcode < 0x60 # Stack, Memory, Storage and Flow Operations
          case op
          when :POP
            stk.pop
          when :MLOAD
            s0 = stk.pop
            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, 32)

            data = Utils.int_array_to_bytes mem.safe_slice(s0, 32)
            stk.push Utils.big_endian_to_int(data)
          when :MSTORE
            s0, s1 = stk.pop, stk.pop
            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, 32)

            32.times.to_a.reverse.each do |i|
              mem[s0+i] = s1 % 256
              s1 /= 256
            end
          when :MSTORE8
            s0, s1 = stk.pop, stk.pop
            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, 1)
            mem[s0] = s1 % 256
          when :SLOAD
            if ext.post_anti_dos_hardfork
              return vm_exception('OUT OF GAS') unless eat_gas(s, Opcodes::SLOAD_SUPPLEMENTAL_GAS)
            end
            s0 = stk.pop
            stk.push ext.get_storage_data(msg.to, s0)
          when :SSTORE
            s0, s1 = stk.pop, stk.pop

            if ext.get_storage_data(msg.to, s0) != 0
              gascost = s1 == 0 ? Opcodes::GSTORAGEKILL : Opcodes::GSTORAGEMOD
              refund = s1 == 0 ? Opcodes::GSTORAGEREFUND : 0
            else
              gascost = s1 == 0 ? Opcodes::GSTORAGEMOD : Opcodes::GSTORAGEADD
              refund = 0
            end

            return vm_exception('OUT OF GAS') if s.gas < gascost

            s.gas -= gascost
            ext.add_refund refund
            ext.set_storage_data msg.to, s0, s1
          when :JUMP
            s0 = stk.pop
            s.pc = s0

            op_new = s.pc < processed_code.size ? processed_code[s.pc][0] : :STOP
            return vm_exception('BAD JUMPDEST') if op_new != :JUMPDEST
          when :JUMPI
            s0, s1 = stk.pop, stk.pop
            if s1 != 0
              s.pc = s0
              op_new = s.pc < processed_code.size ? processed_code[s.pc][0] : :STOP
              return vm_exception('BAD JUMPDEST') if op_new != :JUMPDEST
            end
          when :PC
            stk.push(s.pc - 1)
          when :MSIZE
            stk.push mem.size
          when :GAS
            stk.push s.gas # AFTER subtracting cost 1
          end
        elsif op[0,Opcodes::PREFIX_PUSH.size] == Opcodes::PREFIX_PUSH
          pushnum = op[Opcodes::PREFIX_PUSH.size..-1].to_i
          s.pc += pushnum
          stk.push pushval
        elsif op[0,Opcodes::PREFIX_DUP.size] == Opcodes::PREFIX_DUP
          depth = op[Opcodes::PREFIX_DUP.size..-1].to_i
          stk.push stk[-depth]
        elsif op[0,Opcodes::PREFIX_SWAP.size] == Opcodes::PREFIX_SWAP
          depth = op[Opcodes::PREFIX_SWAP.size..-1].to_i
          temp = stk[-depth - 1]
          stk[-depth - 1] = stk[-1]
          stk[-1] = temp
        elsif op[0,Opcodes::PREFIX_LOG.size] == Opcodes::PREFIX_LOG
          # 0xa0 ... 0xa4, 32/64/96/128/160 + data.size gas
          #
          # a. Opcodes LOG0...LOG4 are added, takes 2-6 stake arguments:
          #      MEMSTART MEMSZ (TOPIC1) (TOPIC2) (TOPIC3) (TOPIC4)
          #
          # b. Logs are kept track of during tx execution exactly the same way
          #    as suicides (except as an ordered list, not a set).
          #
          #    Each log is in the form [address, [topic1, ... ], data] where:
          #    * address is what the ADDRESS opcode would output
          #    * data is mem[MEMSTART, MEMSZ]
          #    * topics are as provided by the opcode
          #
          # c. The ordered list of logs in the transation are expreseed as
          #    [log0, log1, ..., logN].
          #
          depth = op[Opcodes::PREFIX_LOG.size..-1].to_i
          mstart, msz = stk.pop, stk.pop
          topics = depth.times.map {|i| stk.pop }

          s.gas -= msz * Opcodes::GLOGBYTE

          return vm_exception("OOG EXTENDING MEMORY") unless mem_extend(mem, s, mstart, msz)

          data = mem.safe_slice(mstart, msz)
          ext.log(msg.to, topics, Utils.int_array_to_bytes(data))
          if log_log.trace?
            log_log.trace('LOG', to: msg.to, topics: topics, data: data)
          end
        elsif op == :CREATE
          value, mstart, msz = stk.pop, stk.pop, stk.pop

          return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, mstart, msz)

          if ext.get_balance(msg.to) >= value && msg.depth < 1024
            cd = CallData.new mem, mstart, msz

            ingas = s.gas
            if ext.post_anti_dos_hardfork
              ingas = max_call_gas(ingas)
            end
            create_msg = Message.new(msg.to, Constant::BYTE_EMPTY, value, ingas, cd, depth: msg.depth+1)

            o, gas, addr = ext.create create_msg
            if o.true?
              stk.push Utils.coerce_to_int(addr)
              s.gas -= (ingas - gas)
            else
              stk.push 0
              s.gas -= ingas
            end
          else
            stk.push(0)
          end
        elsif op == :CALL
          gas, to, value, memin_start, memin_sz, memout_start, memout_sz = \
            stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop

          return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memin_start, memin_sz)
          return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memout_start, memout_sz)

          to = Utils.zpad_int(to)[12..-1] # last 20 bytes
          extra_gas = (ext.account_exists(to) ? 0 : 1) * Opcodes::GCALLNEWACCOUNT +
            (value > 0 ? 1 : 0) * Opcodes::GCALLVALUETRANSFER +
            (ext.post_anti_dos_hardfork ? 1 : 0) * Opcodes::CALL_SUPPLEMENTAL_GAS
          if ext.post_anti_dos_hardfork
            return vm_exception('OUT OF GAS', needed: extra_gas) if s.gas < extra_gas
            gas = [gas, max_call_gas(s.gas-extra_gas)].min
          else
            return vm_exception('OUT OF GAS', needed: gas+extra_gas) if s.gas < gas+extra_gas
          end

          submsg_gas = gas + Opcodes::GSTIPEND * (value > 0 ? 1 : 0)
          total_gas = gas + extra_gas
          if ext.get_balance(msg.to) >= value && msg.depth < 1024
            s.gas -= total_gas

            cd = CallData.new mem, memin_start, memin_sz
            call_msg = Message.new(msg.to, to, value, submsg_gas, cd, depth: msg.depth+1, code_address: to)

            result, gas, data = ext.apply_msg call_msg
            if result == 0
              stk.push 0
            else
              stk.push 1
              s.gas += gas
              [data.size, memout_sz].min.times do |i|
                mem[memout_start+i] = data[i]
              end
            end
          else
            s.gas -= (total_gas - submsg_gas)
            stk.push(0)
          end
        elsif op == :CALLCODE || op == :DELEGATECALL
          if op == :CALLCODE
            gas, to, value, memin_start, memin_sz, memout_start, memout_sz = \
              stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop
          else
            gas, to, memin_start, memin_sz, memout_start, memout_sz = \
              stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop
            value = 0
          end

          return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memin_start, memin_sz)
          return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memout_start, memout_sz)

          extra_gas = (value > 0 ? 1 : 0) * Opcodes::GCALLVALUETRANSFER +
            (ext.post_anti_dos_hardfork ? 1 : 0) * Opcodes::CALL_SUPPLEMENTAL_GAS
          if ext.post_anti_dos_hardfork
            return vm_exception('OUT OF GAS', needed: extra_gas) if s.gas < extra_gas
            gas = [gas, max_call_gas(s.gas-extra_gas)].min
          else
            return vm_exception('OUT OF GAS', needed: gas+extra_gas) if s.gas < gas+extra_gas
          end

          submsg_gas = gas + Opcodes::GSTIPEND * (value > 0 ? 1 : 0)
          total_gas = gas + extra_gas
          if ext.get_balance(msg.to) >= value && msg.depth < 1024
            s.gas -= total_gas

            to = Utils.zpad_int(to)[12..-1] # last 20 bytes
            cd = CallData.new mem, memin_start, memin_sz

            if ext.post_homestead_hardfork && op == :DELEGATECALL
              call_msg = Message.new(msg.sender, msg.to, msg.value, submsg_gas, cd, depth: msg.depth+1, code_address: to, transfers_value: false)
            elsif op == :DELEGATECALL
              return vm_exception('OPCODE INACTIVE')
            else
              call_msg = Message.new(msg.to, msg.to, value, submsg_gas, cd, depth: msg.depth+1, code_address: to)
            end

            result, gas, data = ext.apply_msg call_msg
            if result == 0
              stk.push 0
            else
              stk.push 1
              s.gas += gas
              [data.size, memout_sz].min.times do |i|
                mem[memout_start+i] = data[i]
              end
            end
          else
            s.gas -= (total_gas - submsg_gas)
            stk.push(0)
          end
        elsif op == :RETURN
          s0, s1 = stk.pop, stk.pop
          return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, s1)
          return peaceful_exit('RETURN', s.gas, mem.safe_slice(s0, s1))
        elsif op == :SUICIDE
          s0 = stk.pop
          to = Utils.zpad_int(s0)[12..-1] # last 20 bytes

          if ext.post_anti_dos_hardfork
            extra_gas = Opcodes::SUICIDE_SUPPLEMENTAL_GAS +
              (ext.account_exists(to) ? 0 : 1) * Opcodes::GCALLNEWACCOUNT
            return vm_exception('OUT OF GAS') unless eat_gas(s, extra_gas)
          end

          xfer = ext.get_balance(msg.to)
          ext.set_balance(to, ext.get_balance(to)+xfer)
          ext.set_balance(msg.to, 0)
          ext.add_suicide(msg.to)

          return 1, s.gas, []
        end
      end
    end

    # Preprocesses code, and determines which locations are in the middle of
    # pushdata and thus invalid
    def preprocess_code(code)
      code = Utils.bytes_to_int_array code
      ops = []

      i = 0
      while i < code.size
        o = Opcodes::TABLE.fetch(code[i], [:INVALID, 0, 0, 0]) + [code[i], 0]
        ops.push o

        if o[0][0,Opcodes::PREFIX_PUSH.size] == Opcodes::PREFIX_PUSH
          n = o[0][Opcodes::PREFIX_PUSH.size..-1].to_i
          n.times do |j|
            i += 1
            byte = i < code.size ? code[i] : 0
            o[-1] = (o[-1] << 8) + byte

            # polyfill, these INVALID ops will be skipped in execution
            ops.push [:INVALID, 0, 0, 0, byte, 0] if i < code.size
          end
        end

        i += 1
      end

      ops
    end

    private

    def log_vm_exit
      @log_vm_exit ||= Logger.new 'eth.vm.exit'
    end

    def log_vm_op
      @log_vm_op ||= Logger.new 'eth.vm.op'
    end

    def log_log
      @log_log ||= Logger.new 'eth.vm.log'
    end

    def vm_exception(error, **kwargs)
      if log_vm_exit.trace?
        log_vm_exit.trace('EXCEPTION', cause: error, **kwargs)
      end
      return 0, 0, []
    end

    def peaceful_exit(cause, gas, data, **kwargs)
      if log_vm_exit.trace?
        log_vm_exit.trace('EXIT', cause: cause, **kwargs)
      end
      return 1, gas, data
    end

    def mem_extend(mem, s, start, sz)
      if sz > 0
        oldsize = mem.size / 32
        old_totalfee = mem_fee oldsize

        newsize = Utils.ceil32(start + sz) / 32
        new_totalfee = mem_fee newsize

        if old_totalfee < new_totalfee
          memfee = new_totalfee - old_totalfee

          if s.gas < memfee
            s.gas = 0
            return false
          end
          s.gas -= memfee

          m_extend = (newsize - oldsize) * 32
          mem.concat([0]*m_extend)
        end
      end

      true
    end

    def data_copy(s, sz)
      if sz > 0
        copyfee = Opcodes::GCOPY * Utils.ceil32(sz) / 32

        if s.gas < copyfee
          s.gas = 0
          return false
        end
        s.gas -= copyfee
      end

      true
    end

    def mem_fee(sz)
      sz * Opcodes::GMEMORY + sz**2 / Opcodes::GQUADRATICMEMDENOM
    end

    def eat_gas(s, amount)
      if s.gas < amount
        s.gas = 0
        false
      else
        s.gas -= amount
        true
      end
    end

    def max_call_gas(gas)
      gas - (gas / Opcodes::CALL_CHILD_LIMIT_DENOM)
    end

  end
end
