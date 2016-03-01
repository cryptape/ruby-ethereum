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

    def execute(ec, msg, code)
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
              trace_data[:memory] = Utils.encode_hex(s.memory.map(&:chr).join)
            else
              trace_data[:sha3memory] = Utils.encode_hex(Utils.keccak256(s.memory.map(&:chr).join))
            end
          end

          if %i(SSTORE SLOAD).include?(_prevop) || steps == 0
            trace_data[:storage] = ec.log_storage(msg.to)
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
        if opcode < 0x10
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
        elsif opcode < 0x20
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

  end
end
