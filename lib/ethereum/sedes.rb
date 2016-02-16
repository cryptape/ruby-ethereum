module Ethereum
  module Sedes
    include RLP::Sedes

    extend self

    def address
      Binary.fixed_length(20, allow_empty: true)
    end

    def int20
      BigEndianInt.new(20)
    end

    def int32
      BigEndianInt.new(32)
    end

    def int256
      BigEndianInt.new(256)
    end

    def hash32
      Binary.fixed_length(32)
    end

    def trie_root
      Binary.fixed_length(32, allow_empty: true)
    end

    def big_endian_int
      RLP::Sedes.big_endian_int
    end

    def binary
      RLP::Sedes.binary
    end

  end
end
