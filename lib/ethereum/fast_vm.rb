# -*- encoding : ascii-8bit -*-

require 'ethereum/fast_vm/call_data'
require 'ethereum/fast_vm/message'
require 'ethereum/fast_vm/state'

module Ethereum
  class FastVM

    STACK_MAX = 1024

    START_BREAKPOINTS = %i(JUMPDEST GAS PC).freeze
    END_BREAKPOINTS = %i(JUMP JUMPI CALL CALLCODE CREATE SUICIDE STOP RETURN INVALID GAS PC)

    include Constant

    OP_INVALID = -1
    Opcodes::TABLE.each do |code, defn|
      const_set "OP_#{defn[0]}", code
    end

    class <<self
      def code_cache
        @code_cache ||= {}
      end

      def execute(*args)
        new.execute(*args)
      end
    end

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

      timestamp = Time.now
      loop do
        return vm_exception('INVALID START POINT') if processed_code.has_key?(s.pc)

        cc = processed_code[s.pc]
        gas, min_stack, max_stack, s.pc = cc[0,4]
        ops = cc[4..-1]

        return vm_exception('OUT OF GAS') if gas > s.gas
        return vm_exception('INCOMPATIBLE STACK LENGTH', min_stack: min_stack, max_stack: max_stack, have: s.stack.size) unless s.stack.size >= min_stack && s.stack.size <= max_stack

        s.gas -= gas

        ops.each do |op|
          if log_vm_exit.trace?
            trace_data = {
              stack: s.stack.map(&:to_s),
              inst: op,
              pc: s.pc-1,
              op: op,
              steps: steps
            }

            if [OP_MLOAD, OP_MSTORE, OP_MSTORE8, OP_SHA3, OP_CALL, OP_CALLCODE, OP_CREATE, OP_CALLDATACOPY, OP_CODECOPY, OP_EXTCODECOPY].include?(_prevop)
              if s.memory.size < 1024
                trace_data[:memory] = Utils.encode_hex(Utils.int_array_to_bytes(s.memory))
              else
                trace_data[:sha3memory] = Utils.encode_hex(Utils.keccak256(Utils.int_array_to_bytes(s.memory)))
              end
            end

            if [OP_SSTORE, OP_SLOAD].include?(_prevop) || steps == 0
              trace_data[:storage] = ext.log_storage(msg.to)
            end

            if steps == 0
              trace_data[:depth] = msg.depth
              trace_data[:address] = msg.to
            end

            log_vm_op.trace('vm', **trace_data)

            steps += 1
            _prevop = op
          end

          # Invalid operation
          return vm_exception('INVALID OP', op: op) if op == OP_INVALID

          # Valid operations
          stk = s.stack
          mem = s.memory
          if op < 0x10 # Stop & Arithmetic Operations
            case op
            when OP_STOP
              return peaceful_exit('STOP', s.gas, [])
            when OP_ADD
              r = (stk.pop + stk.pop) & UINT_MAX
              stk.push r
            when OP_SUB
              r = (stk.pop - stk.pop) & UINT_MAX
              stk.push r
            when OP_MUL
              r = (stk.pop * stk.pop) & UINT_MAX
              stk.push r
            when OP_DIV
              s0, s1 = stk.pop, stk.pop
              stk.push(s1 == 0 ? 0 : s0 / s1)
            when OP_MOD
              s0, s1 = stk.pop, stk.pop
              stk.push(s1 == 0 ? 0 : s0 % s1)
            when OP_SDIV
              s0, s1 = Utils.to_signed(stk.pop), Utils.to_signed(stk.pop)
              r = s1 == 0 ? 0 : ((s0.abs / s1.abs * (s0*s1 < 0 ? -1 : 1)) & UINT_MAX)
              stk.push r
            when OP_SMOD
              s0, s1 = Utils.to_signed(stk.pop), Utils.to_signed(stk.pop)
              r = s1 == 0 ? 0 : ((s0.abs % s1.abs * (s0 < 0 ? -1 : 1)) & UINT_MAX)
              stk.push r
            when OP_ADDMOD
              s0, s1, s2 = stk.pop, stk.pop, stk.pop
              r = s2 == 0 ? 0 : (s0+s1) % s2
              stk.push r
            when OP_MULMOD
              s0, s1, s2 = stk.pop, stk.pop, stk.pop
              r = s2 == 0 ? 0 : Utils.mod_mul(s0, s1, s2)
              stk.push r
            when OP_EXP
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
            when OP_SIGNEXTEND # extend sign from bytes at s0 to left
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
          elsif op < 0x20 # Comparison & Bitwise Logic Operations
            case op
            when OP_LT
              s0, s1 = stk.pop, stk.pop
              stk.push(s0 < s1 ? 1 : 0)
            when OP_GT
              s0, s1 = stk.pop, stk.pop
              stk.push(s0 > s1 ? 1 : 0)
            when OP_SLT
              s0, s1 = Utils.to_signed(stk.pop), Utils.to_signed(stk.pop)
              stk.push(s0 < s1 ? 1 : 0)
            when OP_SGT
              s0, s1 = Utils.to_signed(stk.pop), Utils.to_signed(stk.pop)
              stk.push(s0 > s1 ? 1 : 0)
            when OP_EQ
              s0, s1 = stk.pop, stk.pop
              stk.push(s0 == s1 ? 1 : 0)
            when OP_ISZERO
              s0 = stk.pop
              stk.push(s0 == 0 ? 1 : 0)
            when OP_AND
              s0, s1 = stk.pop, stk.pop
              stk.push(s0 & s1)
            when OP_OR
              s0, s1 = stk.pop, stk.pop
              stk.push(s0 | s1)
            when OP_XOR
              s0, s1 = stk.pop, stk.pop
              stk.push(s0 ^ s1)
            when OP_NOT
              s0 = stk.pop
              stk.push(UINT_MAX - s0)
            when OP_BYTE
              s0, s1 = stk.pop, stk.pop
              if s0 < 32
                stk.push((s1 / 256**(31-s0)) % 256)
              else
                stk.push(0)
              end
            end
          elsif op < 0x40 # SHA3 & Environmental Information
            case op
            when OP_SHA3
              s0, s1 = stk.pop, stk.pop

              s.gas -= Opcodes::GSHA3WORD * (Utils.ceil32(s1) / 32)
              return vm_exception('OOG PAYING FOR SHA3') if s.gas < 0

              return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, s1)

              data = Utils.int_array_to_bytes mem.safe_slice(s0,s1)
              stk.push Utils.big_endian_to_int(Utils.keccak256(data))
            when OP_ADDRESS
              stk.push Utils.coerce_to_int(msg.to)
            when OP_BALANCE
              s0 = stk.pop
              addr = Utils.coerce_addr_to_hex(s0 % 2**160)
              stk.push ext.get_balance(addr)
            when OP_ORIGIN
              stk.push Utils.coerce_to_int(ext.tx_origin)
            when OP_CALLER
              stk.push Utils.coerce_to_int(msg.sender)
            when OP_CALLVALUE
              stk.push msg.value
            when OP_CALLDATALOAD
              stk.push msg.data.extract32(stk.pop)
            when OP_CALLDATASIZE
              stk.push msg.data.size
            when OP_CALLDATACOPY
              mstart, dstart, size = stk.pop, stk.pop, stk.pop

              return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, mstart, size)
              return vm_exception('OOG COPY DATA') unless data_copy(s, size)

              msg.data.extract_copy(mem, mstart, dstart, size)
            when OP_CODESIZE
              stk.push code.size
            when OP_CODECOPY
              mstart, cstart, size = stk.pop, stk.pop, stk.pop

              return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, mstart, size)
              return vm_exception('OOG COPY CODE') unless data_copy(s, size)

              size.times do |i|
                if cstart + i < code.size
                  mem[mstart+i] = code[cstart+i].ord
                else
                  mem[mstart+i] = 0
                end
              end
            when OP_GASPRICE
              stk.push ext.tx_gasprice
            when OP_EXTCODESIZE
              addr = stk.pop
              addr = Utils.coerce_addr_to_hex(addr % 2**160)
              stk.push (ext.get_code(addr) || Constant::BYTE_EMPTY).size
            when OP_EXTCODECOPY
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
          elsif op < 0x50 # Block Information
            case op
            when OP_BLOCKHASH
              s0 = stk.pop
              stk.push Utils.big_endian_to_int(ext.block_hash(s0))
            when OP_COINBASE
              stk.push Utils.big_endian_to_int(ext.block_coinbase)
            when OP_TIMESTAMP
              stk.push ext.block_timestamp
            when OP_NUMBER
              stk.push ext.block_number
            when OP_DIFFICULTY
              stk.push ext.block_difficulty
            when OP_GASLIMIT
              stk.push ext.block_gas_limit
            end
          elsif op < 0x60 # Stack, Memory, Storage and Flow Operations
            case op
            when OP_POP
              stk.pop
            when OP_MLOAD
              s0 = stk.pop
              return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, 32)

              data = 0
              mem[s0, 32].each do |c|
                data = (data << 8) + c
              end

              stk.push data
            when OP_MSTORE
              s0, s1 = stk.pop, stk.pop
              return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, 32)

              32.times.to_a.reverse.each do |i|
                mem[s0+i] = s1 % 256
                s1 /= 256
              end
            when OP_MSTORE8
              s0, s1 = stk.pop, stk.pop
              return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, 1)
              mem[s0] = s1 % 256
            when OP_SLOAD
              s0 = stk.pop
              stk.push ext.get_storage_data(msg.to, s0)
            when OP_SSTORE
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
            when OP_JUMP
              s0 = stk.pop
              s.pc = s0

              op_new = processed_code.has_key?(s.pc) ? processed_code[s.pc][4] : OP_STOP
              return vm_exception('BAD JUMPDEST') if op_new != OP_JUMPDEST
            when OP_JUMPI
              s0, s1 = stk.pop, stk.pop
              if s1.true?
                s.pc = s0
                op_new = processed_code.has_key?(s.pc) ? processed_code[s.pc][4] : OP_STOP
                return vm_exception('BAD JUMPDEST') if op_new != OP_JUMPDEST
              end
            when OP_PC
              stk.push(s.pc - 1)
            when OP_MSIZE
              stk.push mem.size
            when OP_GAS
              stk.push s.gas # AFTER subtracting cost 1
            end
          elsif (op & 0xff) >= OP_PUSH1 && (op & 0xff) <= OP_PUSH32
            stk.push(op >> 8)
          elsif op >= OP_DUP1 && op <= OP_DUP16
            depth = op - OP_DUP1 + 1
            stk.push stk[-depth]
          elsif op >= OP_SWAP1 && op <= OP_SWAP16
            depth = op - OP_SWAP1 + 1
            temp = stk[-depth - 1]
            stk[-depth - 1] = stk[-1]
            stk[-1] = temp
          elsif op >= OP_LOG0 && op <= OP_LOG4
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
            depth = op - OP_LOG0
            mstart, msz = stk.pop, stk.pop
            topics = depth.times.map {|i| stk.pop }

            s.gas -= msz * Opcodes::GLOGBYTE

            return vm_exception("OOG EXTENDING MEMORY") unless mem_extend(mem, s, mstart, msz)

            data = mem.safe_slice(mstart, msz)
            ext.log(msg.to, topics, Utils.int_array_to_bytes(data))
            log_log.trace('LOG', to: msg.to, topics: topics, data: data)
          elsif op == OP_CREATE
            value, mstart, msz = stk.pop, stk.pop, stk.pop

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, mstart, msz)

            if ext.get_balance(msg.to) >= value && msg.depth < 1024
              cd = CallData.new mem, mstart, msz
              create_msg = Message.new(msg.to, Constant::BYTE_EMPTY, value, s.gas, cd, depth: msg.depth+1)

              o, gas, addr = ext.create create_msg
              if o.true?
                stk.push Utils.coerce_to_int(addr)
                s.gas = gas
              else
                stk.push 0
                s.gas = 0
              end
            else
              stk.push(0)
            end
          elsif op == OP_CALL
            gas, to, value, memin_start, memin_sz, memout_start, memout_sz = \
              stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memin_start, memin_sz)
            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memout_start, memout_sz)

            to = Utils.zpad_int(to)[12..-1] # last 20 bytes
            extra_gas = (ext.account_exists(to) ? 0 : 1) * Opcodes::GCALLNEWACCOUNT +
              (value > 0 ? 1 : 0) * Opcodes::GCALLVALUETRANSFER
            submsg_gas = gas + Opcodes::GSTIPEND * (value > 0 ? 1 : 0)
            total_gas = gas + extra_gas

            return vm_exception('OUT OF GAS', needed: total_gas) if s.gas < total_gas

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
          elsif op == OP_CALLCODE
            gas, to, value, memin_start, memin_sz, memout_start, memout_sz = \
              stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memin_start, memin_sz)
            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memout_start, memout_sz)

            extra_gas = (value > 0 ? 1 : 0) * Opcodes::GCALLVALUETRANSFER
            submsg_gas = gas + Opcodes::GSTIPEND * (value > 0 ? 1 : 0)
            total_gas = gas + extra_gas

            return vm_exception('OUT OF GAS', needed: total_gas) if s.gas < total_gas

            if ext.get_balance(msg.to) >= value && msg.depth < 1024
              s.gas -= total_gas

              to = Utils.zpad_int(to)[12..-1] # last 20 bytes
              cd = CallData.new mem, memin_start, memin_sz

              call_msg = Message.new(msg.to, msg.to, value, submsg_gas, cd, depth: msg.depth+1, code_address: to)

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
          elsif op == OP_RETURN
            s0, s1 = stk.pop, stk.pop
            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, s1)
            return peaceful_exit('RETURN', s.gas, mem.safe_slice(s0, s1))
          elsif op == OP_SUICIDE
            s0 = stk.pop
            to = Utils.zpad_int(s0)[12..-1] # last 20 bytes

            xfer = ext.get_balance(msg.to)
            ext.set_balance(to, ext.get_balance(to)+xfer)
            ext.set_balance(msg.to, 0)
            ext.add_suicide(msg.to)

            return 1, s.gas, []
          end


        end
      end
    end

    def preprocess_code(code)
      code = Utils.bytes_to_int_array code

      ops = {}
      cur_chunk = []
      cc_init_pos = 0 # cc = code chunk
      cc_gas_consumption = 0
      cc_stack_change = 0
      cc_min_req_stack = 0 # minimum stack depth before code chunk start
      cc_max_req_stack = STACK_MAX # maximum stack depth before code chunk start

      i = 0
      while i < code.size
        op, in_args, out_args, fee = Opcodes::TABLE.fetch(code[i], [:INVALID, 0, 0, 0])
        opcode, pushval = code[i], 0

        if op[0,Opcodes::PREFIX_PUSH.size] == Opcodes::PREFIX_PUSH
          n = op[Opcodes::PREFIX_PUSH.size..-1].to_i
          n.times do |j|
            i += 1
            byte = i < code.size ? code[i] : 0
            pushval = (pushval << 8) + byte
          end
        end

        i += 1

        opcode = OP_INVALID if op == :INVALID

        cc_gas_consumption += fee
        cc_min_req_stack = [cc_min_req_stack, 0 - cc_stack_change + in_args].max # should leave at least in_args values in stack as arguments of this op
        cc_max_req_stack = [cc_max_req_stack, STACK_MAX - cc_stack_change + in_args - out_args].min # should leave enough stack space for code chunk use
        cc_stack_change = cc_stack_change - in_args + out_args
        cur_chunk.push(opcode + (pushval << 8))

        if END_BREAKPOINTS.include?(op) || i >= code.size ||
            START_BREAKPOINTS.include?(Opcodes::TABLE.fetch(code[i], [:INVALID])[0])
          ops[cc_init_pos] = [
            cc_gas_consumption,
            cc_min_req_stack,
            cc_max_req_stack,
            i # end position
          ] + cur_chunk

          cur_chunk = []
          cc_init_pos = i
          cc_gas_consumption = 0
          cc_stack_change = 0
          cc_min_req_stack = 0
          cc_max_req_stack = STACK_MAX
        end
      end

      ops[i] = [0, 0, STACK_MAX, [0], 0]
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
      if sz > 0 && Utils.ceil32(start + sz) > mem.size
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

  end
end
