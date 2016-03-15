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
        proofs.push ProofConstructor.new
        result = yield
        nodes = proof.decoded_nodes
        [result, nodes]
      ensure
        proofs.pop
      end

      def verify(nodes)
        proofs.push ProofVerifier.new(nodes: nodes)
        yield
      ensure
        proofs.pop
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

      def make_transaction_proof(block, tx)
        result, nodes = record do
          block.apply_transaction(tx)
        end

        nodes
          .map {|x| RLP.encode(x) }
          .uniq
          .map {|x| RLP.decode(x) }
      end

      def verify_transaction_proof(block, tx, nodes)
        verify do
          block.apply_transaction(tx)
        end
        true
      rescue
        puts $!
        false
      end

    end

  end
end
