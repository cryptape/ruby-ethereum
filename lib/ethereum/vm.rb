# -*- encoding : ascii-8bit -*-

require 'ethereum/vm/call_data'
require 'ethereum/vm/message'
require 'ethereum/vm/state'

module Ethereum
  module VM

    class <<self
      def code_cahe
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

      timestamp = Time.now
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
        if Logger.trace?(log_vm_exit.name)
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
            peaceful_exit('STOP', s.gas, [])
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
          when :ADDMOD
            s0, s1, s2 = stk.pop, stk.pop, stk.pop
            r = s2 == 0 ? 0 : (s0+s1) % s2
            stk.push r
          when :MULMOD # TODO: optimizable by FFI?
            s0, s1, s2 = stk.pop, stk.pop, stk.pop
            r = s2 == 0 ? 0 : (s0*s1) % s2
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
              if s1 & mask # extend 1s
                stk.push(s1 | (TT256 - mask))
              else # extend 0s
                stk.push(s1 & (mask - 1))
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

            data = Utils.int_array_to_bytes mem[s0,s1]
            stk.push Utils.big_endian_to_int(Utils.keccak256(data))
          when :ADDRESS
            stk.push Utils.coerce_to_int(msg.to)
          when :BALANCE
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

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, start, size)
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
            addr = stk.pop
            addr = Utils.coerce_addr_to_hex(addr % 2**160)
            stk.push (ext.get_code(addr) || Constant::BYTE_EMPTY).size
          when :EXTCODECOPY
            addr, mstart, cstart, size = stk.pop, stk.pop, stk.pop, stk.pop
            addr = Utils.coerce_addr_to_hex(addr % 2**160)
            extcode = ext.get_code(addr) || Constant::BYTE_EMPTY
            raise ValueError, "extcode must be string" unless extcode.is_a?(String)

            return vm_exception('OOG EXTENDING MEMORY') unless mem_extend(mem, s, start, size)
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
            stk.push Utils.big_endian_to_int(ext.block_hash(s0))
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

            data = Utils.int_array_to_bytes mem[s0, 32]
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

            op_new = s.pc < preprocess_code.size ? processed_code[s.pc][0] : :STOP
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
        end
      end

    end

    private

    def log_vm_exit
      @log_vm_exit ||= Logger.new 'eth.vm.exit'
    end

    def log_vm_op
      @log_vm_op ||= Logger.new 'eth.vm.op'
    end

    def vm_exception(error, **kwargs)
      log_vm_exit.trace('EXCEPTION', cause: error, **kwargs)
      return 0, 0, []
    end

    def peaceful_exit(cause, gas, data, **kwargs)
      log_vm_exit.trace('EXIT', cause: cause, **kwargs)
      return 1, gas, data
    end

    def mem_extend(mem, s, start, sz)
      if size > 0
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
      if sz
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

  end
end
