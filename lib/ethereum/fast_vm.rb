# -*- encoding : ascii-8bit -*-

require 'ethereum/fast_vm/call_data'
require 'ethereum/fast_vm/call'
require 'ethereum/fast_vm/message'
require 'ethereum/fast_vm/state'

module Ethereum
  class FastVM

    STACK_MAX = 1024

    START_BREAKPOINTS = %i(JUMPDEST GAS PC BREAKPOINT).freeze
    END_BREAKPOINTS = %i(JUMP JUMPI CALL CALLCODE CALLSTATIC CREATE SUICIDE STOP RETURN INVALID GAS PC BREAKPOINT)

    include Constant
    include Config

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

    def execute(ext, msg, code, breaking: false)
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

      c_exstate = Utils.shardify EXECUTION_STATE, msg.left_bound
      c_log = Utils.shardify LOG, msg.left_bound
      c_creator = Utils.shardify CREATOR, msg.left_bound

      timestamp = Time.now
      loop do
        return vm_exception('INVALID START POINT') unless processed_code.has_key?(s.pc)

        cc = processed_code[s.pc]
        gas, min_stack, max_stack, s.pc = cc[0,4]
        ops = cc[4..-1]

        return vm_exception('OUT OF GAS') if gas > s.gas
        return vm_exception('INCOMPATIBLE STACK LENGTH', min_stack: min_stack, max_stack: max_stack, have: s.stack.size) unless s.stack.size >= min_stack && s.stack.size <= max_stack

        s.gas -= gas

        ops.each do |op|
          if Logger.trace?(log_vm_exit.name)
            trace_data = {
              stack: s.stack.map(&:to_s),
              approx_gas: s.gas,
              inst: op,
              pc: s.pc-1,
              op: op % 256,
              steps: steps
            }

            if [OP_MLOAD, OP_MSTORE, OP_MSTORE8, OP_SHA3, OP_CALL, OP_CALLCODE, OP_CREATE, OP_CALLDATACOPY, OP_CODECOPY, OP_EXTCODECOPY].include?(_prevop)
              if s.memory.size < 1024
                trace_data[:memory] = Utils.encode_hex(Utils.int_array_to_bytes(s.memory))
              else
                trace_data[:sha3memory] = Utils.encode_hex(Utils.keccak256(Utils.int_array_to_bytes(s.memory)))
              end
            end

            #if [OP_SSTORE, OP_SLOAD].include?(_prevop) || steps == 0
            #  trace_data[:storage] = ext.log_storage(msg.to)
            #end

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
              addr = validate_and_get_address s0, msg
              return vm_exception('OUT OF RANGE') unless addr
              stk.push Utils.big_endian_to_int(ext.get_storage(ETHER, addr))
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
            when OP_EXTCODESIZE
              s0 = stk.pop
              addr = validate_and_get_address s0, msg
              return vm_exception('OUT OF RANGE') unless addr
              stk.push (ext.get_storage_at(addr, BYTE_EMPTY) || BYTE_EMPTY).size
            when OP_EXTCODECOPY
              addr = stk.pop
              addr = validate_and_get_address addr, msg
              return vm_exception('OUT OF RANGE') unless addr

              mstart, cstart, size = stk.pop, stk.pop, stk.pop
              extcode = ext.get_storage_at(addr, BYTE_EMPTY) || BYTE_EMPTY
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
            when OP_MCOPY
              to, from, size = stk.pop, stk.pop, stk.pop

              return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, to, size)
              return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, from, size)
              return vm_exception('OOG COPY DATA') unless data_copy(s, size)

              data = mem[from, size]
              size.times {|i| mem[to+i] = data[i] }
            end
          elsif op < 0x50 # Block Information
            case op
            when OP_BLOCKHASH
              s0 = stk.pop
              stk.push Utils.big_endian_to_int(ext.get_storage(BLOCKHASHES, s0))
            when OP_COINBASE
              stk.push Utils.big_endian_to_int(ext.get_storage(PROPOSER, WORD_ZERO))
            when OP_NUMBER
              stk.push Utils.big_endian_to_int(ext.get_storage(BLKNUMBER, WORD_ZERO))
            when OP_DIFFICULTY
              stk.push ext.block_difficulty
            when OP_GASLIMIT
              stk.push GASLIMIT
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
              stk.push Utils.big_endian_to_int(ext.get_storage(msg.to, s0))
            when OP_SSTORE, OP_SSTOREEXT
              if op == OP_SSTOREEXT
                shard = stk.pop
                return vm_exception('OUT OF RANGE') unless validate_and_get_address(shard << ADDR_BYTES*8) # FIXME: shouldn't be ADDR_BASE_BYTES?
                toaddr = Utils.shardify(msg.to, shard)
              else
                toaddr = msg.to
              end

              s0, s1 = stk.pop, stk.pop

              if ext.get_storage(msg.to, s0).true?
                gascost = s1 == 0 ? Opcodes::GSTORAGEKILL : Opcodes::GSTORAGEMOD
                refund = s1 == 0 ? Opcodes::GSTORAGEREFUND : 0
              else
                gascost = s1 == 0 ? Opcodes::GSTORAGEMOD : Opcodes::GSTORAGEADD
                refund = 0
              end

              gascost /= 2 if toaddr == CASPER
              return vm_exception('OUT OF GAS') if s.gas < gascost

              s.gas -= gascost
              ext.set_storage toaddr, s0, s1

              # Copy code to new shard
              if op == OP_SSTOREEXT
                if ext.get_storage(toaddr, BYTE_EMPTY).false?
                  ext.set_storage toaddr, ext.get_storage(msg.to)
                end
              end
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
            when OP_SLOADEXT
              shard, key = stk.pop, stk.pop
              return vm_exception('OUT OF RANGE') unless validate_and_get_address(shard << ADDR_BYTES*8) # FIXME: should be ADDR_BASE_BYTES??
              toaddr = Utils.shardify msg.to, shard

              stk.push Utils.big_endian_to_int(ext.get_storage(toaddr, key))

              if ext.get_storage(toaddr, BYTE_EMPTY).false?
                ext.set_storage toaddr, ext.get_storage(msg.to)
              end
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
            depth = op - OP_LOG0
            mstart, msz = stk.pop, stk.pop

            return vm_exception("OOG EXTENDING MEMORY") unless mem_extend(mem, s, mstart, msz)

            topics = 4.times.map {|i| i < depth ? stk.pop : 0 }
            log_data = topics.map {|t| Utils.zpad_int(t) }.join.map(&:ord) + mem[mstart, msz]

            log_data = CallData.new log_data, 0, log_data.size
            log_gas = Opcodes::GLOGBASE +
              Opcodes::GLOGBYTE * msz + Opcodes::GLOGTOPIC * topics.size # FIXME: bug, topics size is always 4!

            s.gas -= log_gas
            return vm_exception('OUT OF GAS', needed: log_gas) if s.gas < log_gas # FIXME: should check before acutally subtraction???

            log_msg = Message.new msg.to, c_log, 0, log_gas, log_data, depth: msg.depth+1, code_address: c_log
            result, gas, data = ext.apply_msg log_msg, BYTE_EMPTY

            #if ([mstart, msz] + topics).include?(3141592653589)
            #  raise "Testing exception triggered!"
            #end
          elsif op == OP_CREATE
            value, mstart, msz = stk.pop, stk.pop, stk.pop

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, mstart, msz)

            code = mem[mstart, msz]
            create_msg = Message.new msg.to, c_creator, value, msg.gas-20000, code, depth: msg.depth+1, code_address: c_creator
            result, gas, data = ext.apply_msg create_msg, BYTE_EMPTY
            if result.true?
              addr = Utils.shardify Utils.keccak256(msg.to[-ADDR_BASE_BYTES..-1] + code)[(32-ADDR_BASE_BYTES)..-1], msg.left_bound
              stk.push Utils.big_endian_to_int(addr)
            else
              stk.push(0)
            end
          elsif op == OP_CALL
            gas, to, value, memin_start, memin_sz, memout_start, memout_sz = \
              stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memin_start, memin_sz)

            to = validate_and_get_address to, msg
            return vm_exception('OUT OF RANGE') unless to

            extra_gas = (value > 0 ? 1 : 0) * Opcodes::GCALLVALUETRANSFER
            submsg_gas = gas + Opcodes::GSTIPEND * (value > 0 ? 1 : 0)
            total_gas = gas + extra_gas

            return vm_exception('OUT OF GAS', needed: total_gas) if s.gas < total_gas

            if Utils.big_endian_to_int(ext.get_storage(ETHER, msg.to)) >= value && msg.depth < 1024
              s.gas -= total_gas

              cd = CallData.new mem, memin_start, memin_sz
              call_msg = Message.new(msg.to, to, value, submsg_gas, cd,
                                     depth: msg.depth+1, code_address: to)

              codehash = ext.get_storage to, BYTE_EMPTY
              code = codehash.true? ? ext.unhash(codehash) : BYTE_EMPTY
              result, gas, data = ext.apply_msg call_msg, code
              if result == 0
                stk.push 0
              else
                stk.push 1

                return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memout_start, [data.size, memout_sz].min)

                s.gas += gas
                [data.size, memout_sz].min.times do |i|
                  mem[memout_start+i] = data[i]
                end
              end
            else
              s.gas -= (total_gas - submsg_gas)
              stk.push(0)
            end
          elsif op == OP_CALLCODE || op == OP_DELEGATECALL
            if op == OP_CALLCODE
              gas, to, value, memin_start, memin_sz, memout_start, memout_sz = \
                stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop
            else
              gas, to, memin_start, memin_sz, memout_start, memout_sz = \
                stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop
              value = msg.value
            end

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memin_start, memin_sz)
            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, memout_start, memout_sz)

            extra_gas = (value > 0 ? 1 : 0) * Opcodes::GCALLVALUETRANSFER
            submsg_gas = gas + Opcodes::GSTIPEND * (value > 0 ? 1 : 0)
            total_gas = gas + extra_gas

            return vm_exception('OUT OF GAS', needed: total_gas) if s.gas < total_gas

            if Utils.big_endian_to_int(ext.get_storage(ETHER, msg.to)) >= value && msg.depth < 1024
              s.gas -= total_gas

              to = validate_and_get_address to, msg
              return vm_exception('OUT OF RANGE') unless to
              cd = CallData.new mem, memin_start, memin_sz

              if op == OP_CALLCODE
                call_msg = Message.new(msg.to, msg.to, value, submsg_gas, cd, depth: msg.depth+1, code_address: to)
              elsif op == OP_DELEGATECALL
                call_msg = Message.new(msg.sender, msg.to, value, submsg_gas, cd, depth: msg.depth+1, code_address: to, transfers_value: false)
              end

              codehash = ext.get_storage to, BYTE_EMPTY
              code = codehash.true? ? ext.unhash(codehash) : BYTE_EMPTY
              result, gas, data = ext.apply_msg call_msg, code

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
          elsif op == OP_CALLSTATIC
            submsg_gas, codestart, codesz, datastart, datasz, outstart, outsz =
              stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop, stk.pop

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, codestart, codesz)
            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, datastart, datasz)
            return vm_exception('OUT OF GAS', needed: submsg_gas) if s.gas < submsg_gas

            s.gas -= submsg_gas

            cd = CallData.new mem, datastart, datasz
            call_msg = Message.new msg.sender, msg.to, 0, submsg_gas, cd, depth: msg.depth+1

            result, gas, data = ext.static_msg(call_msg, Utils.int_array_to_bytes(mem[codestart, codesz]))

            if result == 0
              stk.push 0
            else
              stk.push 1
              s.gas += gas

              return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, outstart, outsz) # FIXME: should be [outsz, data.size].min

              [data.size, outsz].min.times {|i| mem[outstart+i] = data[i] }
            end
          elsif op == OP_RETURN
            s0, s1 = stk.pop, stk.pop
            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s0, s1)
            return peaceful_exit('RETURN', s.gas, mem.safe_slice(s0, s1))
          elsif op == OP_SLOADBYTES || op == OP_SLOADEXTBYTES
            if op == OP_SLOADEXTBYTES
              shard = stk.pop
              return vm_exception('OUT OF RANGE') unless validate_and_get_address(shard << (ADDR_BYTES*8)) # FIXME: should be ADDR_BASE_BYTES??
              toaddr = Utils.shardify msg.to, shard
            else
              toaddr = msg.to
            end

            s0, s1, s2 = stk.pop, stk.pop, stk.pop
            data = Utils.bytes_to_int_array ext.get_storage(toaddr, s0)

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s1, [data.size, s2].min)

            [data.size, s2].min.times {|i| mem[s1+i] = data[i] }

            # Copy code to new shard
            if op == OP_SLOADEXTBYTES
              if ext.get_storage(toaddr, BYTE_EMPTY).false?
                ext.set_storage toaddr, ext.get_storage(msg.to)
              end
            end
          elsif op == OP_BREAKPOINT
            return peaceful_exit('RETURN', s.gas, mem) if breaking
          elsif op == OP_RNGSEED
            s0 = stk.pop
            stk.push Utils.big_endian_to_int(ext.get_storage(RNGSEEDS, s0))
          elsif op == OP_SSIZEEXT
            shard, key = stk.pop, stk.pop
            return vm_exception('OUT OF RANGE') unless validate_and_get_address(shard << (ADDR_BYTES*8)) # FIXME: should be ADDR_BASE_BYTES???
            toaddr = Utils.shardify msg.to, shard
            stk.push ext.get_storage(toaddr, key).size

            if ext.get_storage(toaddr, BYTE_EMPTY).false?
              ext.set_storage toaddr, ext.get_storage(msg.to)
            end
          elsif op == OP_SSTOREBYTES || op == OP_SSTOREEXTBYTES
            if op == OP_SSTOREEXTBYTES
              shard = stk.pop
              return vm_exception('OUT OF RANGE') unless validate_and_get_address(shard << (ADDR_BYTES*8))
              toaddr = Utils.shardify msg.to, shard
            else
              toaddr = msg.to
            end

            s0, s1, s2 = stk.pop, stk.pop, stk.pop

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, s1, s2)

            data = Utils.int_array_to_bytes mem[s1, s2]
            ext.set_storage toaddr, s0, data # FIXME: storage slot capacity is unlimited?

            if op == OP_SSTOREEXTBYTES
              if ext.get_storage(toaddr, BYTE_EMPTY).false?
                ext.set_storage toaddr, ext.get_storage(msg.to)
              end
            end
          elsif op == OP_SSIZE
            s0 = stk.pop
            stk.push ext.get_storage(msg.to, s0).size
          elsif op == OP_STATEROOT
            s0 = stk.pop
            stk.push Utils.big_endian_to_int(ext.get_storage(STATEROOTS, s0))
          elsif op == OP_TXGAS
            stk.push Utils.big_endian_to_int(ext.get_storage(c_exstate, TXGAS))
          elsif op == OP_SUICIDE
            s0 = stk.pop
            to = validate_and_get_address s0, msg
            return vm_exception('OUT OF RANGE') unless to

            xfer = Utils.big_endian_to_int ext.get_storage(ETHER, msg.to)
            ext.set_storage(ETHER, to, Utils.big_endian_to_int(ext.get_storage(EHTER, TO)) + xfer)
            ext.set_storage(ETHER, msg.to, 0)
            ext.set_storage(msg.to, BYTE_EMPTY, BYTE_EMPTY)

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

      ops[i] = [0, 0, STACK_MAX, i, 0]
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
      puts "VM EXCEPTION error: #{error} kwargs: #{kwargs}"
      log_vm_exit.trace('EXCEPTION', cause: error, **kwargs)
      return 0, 0, []
    end

    def peaceful_exit(cause, gas, data, **kwargs)
      log_vm_exit.trace('EXIT', cause: cause, **kwargs)
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

    def mem_fee(sz)
      sz * Opcodes::GMEMORY + sz**2 / Opcodes::GQUADRATICMEMDENOM
    end

    def validate_and_get_address(addr_int, msg)
      shard_id = (addr_int >> (ADDR_BASE_BYTES*8)) % MAXSHARDS
      return Utils.int_to_addr(addr_int) if shard_id >= msg.left_bound && shard_id < msg.right_bound

      puts "FAIL - left: #{msg.left_bound} at: #{shard_id} right: #{msg.right_bound}"
      false
    end

  end
end
