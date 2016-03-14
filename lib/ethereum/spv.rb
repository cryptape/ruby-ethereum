# -*- encoding : ascii-8bit -*-

require 'ethereum/spv/proof'
require 'ethereum/spv/proof_constructor'
require 'ethereum/spv/proof_verifier'

module Ethereum
  module SPV

    class <<self

      def proofs
        @proofs ||= []
      end

      def proof
        proofs.last
      end

      def grabbing(node)
        proof.grabbing node if proof
      end

      def store(node)
        proof.store node if proof
      end

      def record
        self.proofs.push ProofConstructor.new
        result = yield
        nodes = proof.decoded_nodes
        self.proofs.pop
        [result, nodes]
      end

      def mode
        case proof
        when ProofConstructor
          :record
        when ProofVerifier
          :verify
        else
          nil
        end
      end

      def mk_transaction_proof(block, tx)
        result, nodes = record do
          block.apply_transaction(tx)
        end

        nodes
          .map {|x| RLP.encode(x) }
          .uniq
          .map {|x| RLP.decode(x) }
      end
    end

  end
end
