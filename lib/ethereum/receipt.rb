# -*- encoding : ascii-8bit -*-

module Ethereum
  class Receipt
    include RLP::Sedes::Serializable

    extend Sedes

    set_serializable_fields(
      state_root: trie_root,
      gas_used: big_endian_int,
      bloom: int256,
      logs: RLP::Sedes::CountableList.new(Log)
    )

    def initialize(state_root, gas_used, logs, bloom=nil)
      super(state_root, gas_used, nil, logs)
      raise ArgumentError, "Invalid bloom filter" if bloom && bloom != self.bloom
    end

    def bloom
      bloomables = logs.map {|l| l.bloomables }
      Bloom.from_array bloomables.flatten
    end

  end
end
