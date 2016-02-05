require 'set'

module Ethereum
  class SPVProof

    MODES = %i(recording verifying)

    def initialize
      @proving = false

      @mode_stack    = []
      @exempts_stack = []
      @nodes_stack   = []
    end

    def push(mode, nodes=[])
      raise ArgumentError, "invalid mode" unless MODES.include?(mode)

      @proving = true

      @mode_stack.push mode
      @exempts_stack.push Set.new

      if mode == :verifying
        data_set = nodes.map {|n| rlp_encode(n) }.to_set
        @nodes_stack.push data_set
      else
        @nodes_stack.push Set.new
      end
    end

    def pop
      @mode_stack.pop
      @exempts_stack.pop
      @nodes_stack.pop

      @proving = false if @mode_stack.empty?
    end

    def proving?
      @proving
    end

    def mode
      @mode_stack.last
    end

    def exempts
      @exempts_stack.last
    end

    def nodes
      @nodes_stack.last
    end

    def decoded_nodes
      nodes.map {|n| RLP.decode(n) }
    end

    def add_node(node)
      node = FastRLP.encode node
      nodes.add(node) unless exempts.include?(node)
    end

    def add_exempt(node)
      exempts.add FastRLP.encode(node)
    end

  end
end
