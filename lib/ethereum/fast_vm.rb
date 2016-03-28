# -*- encoding : ascii-8bit -*-

require 'ethereum/fast_vm/call_data'
require 'ethereum/fast_vm/message'
require 'ethereum/fast_vm/state'

module Ethereum
  class FastVM

    STACK_MAX = 1024

    START_BREAKPOINTS = %i(JUMPDEST GAS PC).freeze
    END_BREAKPOINTS = %i(JUMP JUMPI CALL CALLCODE CREATE SUICIDE STOP RETURN INVALID GAS PC)

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

        opcode = -1 if op == :INVALID

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

  end
end
