# -*- encoding : ascii-8bit -*-

module Ethereum
  class VM

    class CallData

      attr :size

      def initialize(parent_memory, offset=0, size=nil)
        @data = parent_memory
        @offset = offset
        @size = size || @data.size
        @rlimit = @offset + @size
      end

      def extract_all
        d = @data.safe_slice(@offset, @size)
        d += [0] * (@size - d.size)
        Utils.int_array_to_bytes(d)
      end

      def extract32(i)
        return 0 if i >= @size

        right = [@offset+i+32, @rlimit].min
        o = @data.safe_slice(@offset+i...right)
        Utils.bytearray_to_int(o + [0]*(32-o.size))
      end

      def extract_copy(mem, memstart, datastart, size)
        size.times do |i|
          mem[memstart+i] = datastart+i < @size ? @data[@offset+datastart+i] : 0
        end
      end

    end

  end
end
