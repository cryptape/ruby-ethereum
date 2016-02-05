require 'digest/sha3'

module Ethereum
  module Utils

    def keccak_256(x)
      Digest::SHA3.new(256).digest(x)
    end

  end
end
