# -*- encoding : ascii-8bit -*-

require 'set'

module Ethereum
  module SPV
    class ProofVerifier < Proof

      def initialize(nodes, exempts: [])
        nodes = nodes.map {|n| RLP.encode(n) }.to_set
        super(nodes: nodes, exempts: exempts)
      end

      def grabbing(node)
        raise InvalidSPVProof unless nodes.include?(FastRLP.encode(node))
      end

      def store(node)
        add_node node.dup
      end

    end
  end
end
