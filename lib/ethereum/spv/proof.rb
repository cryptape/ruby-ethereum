# -*- encoding : ascii-8bit -*-

require 'set'

module Ethereum
  module SPV
    class Proof

      attr :nodes, :exempts

      def initialize(nodes: Set.new, exempts: [])
        @nodes = nodes
        @exempts = exempts
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
end
