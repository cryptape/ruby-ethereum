require 'digest/sha3'

module Ethereum
  module Utils

    extend self

    def keccak_256(x)
      Digest::SHA3.new(256).digest(x)
    end

    def keccak_rlp(x)
      keccak_256 RLP.encode(x)
    end

  end
end
