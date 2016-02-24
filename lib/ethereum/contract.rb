# -*- encoding : ascii-8bit -*-

module Ethereum
  class Contract

    class <<self
      def make_address(sender, nonce)
        Utils.keccak256_rlp([Utils.normalize_address(sender), nonce])[12..-1]
      end
    end

  end
end
