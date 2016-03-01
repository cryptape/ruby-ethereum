# -*- encoding : ascii-8bit -*-

module Ethereum
  class VM
    class State

      attr_accessor :memory, :stack, :pc, :gas

      def initialize(**kwargs)
        @memory = []
        @stack = []
        @pc = 0
        @gas = 0

        kwargs.each do |k,v|
          class <<self
            self
          end.class_eval("attr_accessor :#{k}")
          send :"#{k}=", v
        end
      end

    end
  end
end
