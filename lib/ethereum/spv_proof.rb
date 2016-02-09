require 'set'

module Ethereum
  class SPVProof

    MODES = %i(recording verifying)

    class InvalidSPVProof < StandardError; end

    class <<self
      def record
        # TODO: see produce_spv_proof in pyethereum
      end

      def verify
        # TODO: see verify_spv_proof in pyethereum
      end
    end

    def initialize
      @proving = false

      @mode_stack    = []
      @exempts_stack = []
      @nodes_stack   = []
    end

    def grab(node)
      return unless proving?

      case mode
      when :recording
        add_node node.dup
      when :verifying
        raise InvalidSPVProof.new("Proof invalid!") unless nodes.include?(FastRLP.encode(node))
      else
        raise "Cannot handle proof mode: #{mode}"
      end
    end

    def store(node)
      return unless proving?

      case mode
      when :recording
        add_exempt node.dup
      when :verifying
        add_node node.dup
      else
        raise "Cannot handle proof mode: #{mode}"
      end
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
