# -*- encoding : ascii-8bit -*-

require 'set'

module Ethereum
  module SPV
    class ProofConstructor < Proof

      def grabbing(node)
        add_node node.dup
      end

      def store(node)
        add_exempt node.dup
      end

    end
  end
end
